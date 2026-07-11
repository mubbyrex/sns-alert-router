output "rule_arns" {
  description = "Map of logical rule name to its EventBridge rule ARN."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.arn }
}
