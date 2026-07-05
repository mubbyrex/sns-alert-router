variable "name_prefix" {
  description = "Prefix for the example's SNS topic names (e.g. \"<name_prefix>-critical\")."
  type        = string
  default     = "alert-router-example"
}

variable "slack_team_id" {
  description = <<-EOT
    Slack workspace (team) ID that AWS Chatbot is authorized against. No
    default — this is workspace-specific. Find it in the AWS Chatbot / Amazon Q
    Developer console after connecting your Slack workspace, or in Slack under
    workspace settings.
  EOT
  type        = string
}

variable "slack_channel_id" {
  description = <<-EOT
    Slack channel ID (not the channel name) the critical alerts go to. No
    default. In the Slack app, right-click the channel -> View channel details;
    the ID (starts with C) is at the bottom of that panel.
  EOT
  type        = string
}

variable "oncall_email_addresses" {
  description = "Email addresses subscribed to all severity tiers. Each must confirm its SNS subscription before delivery works."
  type        = list(string)
  default     = ["oncall@example.com"]
}
