output "subscription_arns" {
  description = "Map of \"<tier>::<email>\" to SNS subscription ARN. Values read PendingConfirmation until the recipient confirms."
  value       = { for k, sub in aws_sns_topic_subscription.this : k => sub.arn }
}
