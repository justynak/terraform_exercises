data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

### Instance role: pull from ECR + push to CloudWatch Logs
resource "aws_iam_role" "ec2_role" {
  name = "ec2-ecr-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Allows the built-in SSM agent + Session Manager (debug access, no ingress).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "logs_write" {
  name = "logs-write"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.app.arn}:*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ecr-logs-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "application_server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet_a.id
  vpc_security_group_ids = [aws_security_group.application_server_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -uxo pipefail

    # Log everything so it survives even if a step fails.
    exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

    dnf install -y docker
    systemctl enable --now docker
  
    # --- Pull image from ECR via the interface endpoints ---
    REPO_URL="${aws_ecr_repository.app.repository_url}"
    REGISTRY="$${REPO_URL%%/*}"

    aws ecr get-login-password --region "${data.aws_region.current.name}" \
      | docker login --username AWS --password-stdin "$REGISTRY"

    # Retry: interface endpoints may take a moment to resolve DNS.
    pulled=false
    for i in $(seq 1 10); do
      if docker pull "$REPO_URL:v1"; then pulled=true; break; fi
      echo "pull retry $i..."
      sleep 15
    done
    if [ "$pulled" != true ]; then
      echo "ERROR: could not pull $REPO_URL:v1 after retries" >&2
      exit 1
    fi

    # --- Run it, streaming stdout/stderr straight to CloudWatch Logs ---
    # The awslogs driver uses the instance role + the `logs` VPC endpoint;
    # no CloudWatch agent needed. Do NOT add `awslogs-create-stream`: that
    # log-opt is missing on the AL2023 docker package and `docker run` aborts
    # with "unknown log opt" before the container is created.
    REGION="${data.aws_region.current.name}"
    GROUP="${aws_cloudwatch_log_group.app.name}"
    STREAM="$(hostname)"

    if ! RUN_ERR="$(docker run -d --name hello-container --restart unless-stopped \
      --log-driver=awslogs \
      --log-opt awslogs-region="$REGION" \
      --log-opt awslogs-group="$GROUP" \
      --log-opt awslogs-stream="$STREAM" \
      --log-opt awslogs-create-group=true \
      "$REPO_URL:v1" 2>&1)"; then
      echo "ERROR: docker run failed: $RUN_ERR" >&2
      exit 1
    fi

    # Guard against the awslogs driver silently falling back to json-file
    # (container runs, but nothing reaches CloudWatch).
    driver="$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' hello-container)"
    if [ "$driver" != "awslogs" ]; then
      echo "ERROR: container is using '$driver' logging, not awslogs" >&2
      exit 1
    fi
  EOF

  tags = { Name = "app-server" }

  depends_on = [
    aws_vpc_endpoint.ecr,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.logs,
    aws_vpc_endpoint.ssm,
    terraform_data.image_push,
  ]

  # Recreate the instance (which re-pulls the image) whenever a new image is
  # built & pushed, i.e. when terraform_data.image_push is replaced.
  lifecycle {
    replace_triggered_by = [terraform_data.image_push]
  }
}

