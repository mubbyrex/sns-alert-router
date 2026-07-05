output "chatbot_configuration_arn" {
  description = "ARN of the created AWS Chatbot Slack channel configuration."
  value       = aws_chatbot_slack_channel_configuration.this.chat_configuration_arn
}
