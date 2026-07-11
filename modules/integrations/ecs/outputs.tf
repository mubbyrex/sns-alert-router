output "rule_arns" {
  description = "Map of logical rule name to its EventBridge rule ARN."
  value = {
    task-stopped           = aws_cloudwatch_event_rule.task_stopped.arn
    deployment-failed      = aws_cloudwatch_event_rule.deployment_failed.arn
    deployment-in-progress = aws_cloudwatch_event_rule.deployment_in_progress.arn
  }
}
