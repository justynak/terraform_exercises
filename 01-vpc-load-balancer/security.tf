# Allow HTTP from the internet to the ALB.
resource "aws_security_group" "alb_sg" {
  name        = "app-lb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# Allow HTTP to the instances only from the ALB security group.
resource "aws_security_group" "instance_sg" {
  name        = "app-instance-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "instance_sg" }
}
