# --- Scaling policies --------------------------------------------------

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  autoscaling_group_name = aws_autoscaling_group.app_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  autoscaling_group_name = aws_autoscaling_group.app_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
}

# --- CloudWatch alarms driving the policies ----------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 70

  dimensions    = { AutoScalingGroupName = aws_autoscaling_group.app_server.name }
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu_low"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5 # scale down more cautiously than up
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 30

  dimensions    = { AutoScalingGroupName = aws_autoscaling_group.app_server.name }
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}
