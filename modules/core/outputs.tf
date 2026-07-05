output "topic_arns" {
  description = "Map of severity tier name to its SNS topic ARN. Consumed by receiver modules."
  value       = { for k, v in aws_sns_topic.this : k => v.arn }
}
