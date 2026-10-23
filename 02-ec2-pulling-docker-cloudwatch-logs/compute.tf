data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "application_server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet_a.id
  vpc_security_group_ids = [aws_security_group.application_server_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    region         = data.aws_region.current.name
    repository_url = aws_ecr_repository.app.repository_url
    image_tag      = "v1"
    log_group_name = aws_cloudwatch_log_group.app.name
  })
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

