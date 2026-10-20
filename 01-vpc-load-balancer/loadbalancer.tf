# Pool of EC2 instances behind the ALB.
resource "aws_lb_target_group" "lb_target_group" {
  name        = "app-lb-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.app_vpc.id

  health_check {
    path = "/"
  }
}

# Application Load Balancer, placed in the public subnets.
resource "aws_lb" "load_balancer" {
  name                       = "app-lb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = [aws_subnet.public_a_subnet.id, aws_subnet.public_b_subnet.id]
  security_groups            = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false
}

# Forward port 80 to the target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_target_group.arn
  }
}
