# Launch template for the app instances (AL2023 + echo server).
resource "aws_launch_template" "app_server" {
  name_prefix   = "app-server-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  user_data = base64encode(<<-EOF
#!/bin/bash

# Write the echo server script
cat > /opt/echo_server.py <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"Hello from {socket.gethostname()}!\nPath: {self.path}\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())


HTTPServer(("0.0.0.0", 80), H).serve_forever()
PY

# Run it as a systemd service so it survives and restarts on failure
cat > /etc/systemd/system/echo-server.service <<'UNIT'
[Unit]
Description=Echo HTTP server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/echo_server.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now echo-server.service
EOF
  )

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.instance_sg.id]
  }
}

# Auto Scaling Group spanning the two private subnets.
resource "aws_autoscaling_group" "app_server" {
  name                      = "app-server-asg"
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  vpc_zone_identifier       = [aws_subnet.private_a_subnet.id, aws_subnet.private_b_subnet.id]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app_server.id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value               = var.instance_name
    propagate_at_launch = true
  }
}

# Register the ASG with the ALB target group.
resource "aws_autoscaling_attachment" "asg_lb" {
  autoscaling_group_name = aws_autoscaling_group.app_server.id
  lb_target_group_arn    = aws_lb_target_group.lb_target_group.arn
}
