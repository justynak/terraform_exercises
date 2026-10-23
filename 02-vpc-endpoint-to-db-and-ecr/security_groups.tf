#############################
##### Security groups
#############################
resource "aws_security_group" "application_server_sg" {
  name        = "app-server-sg"
  description = "Application server (EC2) security group"
  vpc_id      = aws_vpc.main_vpc.id

  # no ingress for now, as ec2 is not reachable from outside (no alb just yet)

  egress {
    description = "Interface endpoints (ECR, Logs, SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description     = "S3 via gateway endpoint (dnf repos, ECR layers)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }

  tags = { Name = "app-server-sg" }
}

resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  description = "VPC interface endpoints (ECR, Logs, SSM) security group"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.application_server_sg.id]
  }

  # Endpoints only need to reply to the client; scope to the VPC CIDR.
  egress {
    description = "Responses back to VPC clients"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  tags = { Name = "vpc-endpoint-sg" }
}
