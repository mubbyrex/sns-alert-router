variable "configuration_name" {
  description = <<-EOT
    Unique name for this Chatbot Slack channel configuration and its dedicated
    IAM role. Has no default so multiple receiver instances in one account do
    not collide.
  EOT
  type        = string
}

variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from module.core's topic_arns output."
  type        = map(string)
}

variable "severity_tiers" {
  description = "Which keys of topic_arns this receiver subscribes to. Must be a subset of topic_arns' keys."
  type        = list(string)

  validation {
    condition     = length(setsubtract(toset(var.severity_tiers), toset(keys(var.topic_arns)))) == 0
    error_message = "severity_tiers must be a subset of topic_arns keys. Unknown tier(s): ${join(", ", setsubtract(toset(var.severity_tiers), toset(keys(var.topic_arns))))}."
  }
}

variable "slack_team_id" {
  description = "Slack workspace ID. Find this in Slack under workspace settings, or via the AWS Chatbot console's 'Configure new client' flow."
  type        = string
}

variable "slack_channel_id" {
  description = "Slack channel ID (not the channel name) to receive alerts."
  type        = string
}

variable "logging_level" {
  description = "Chatbot logging level (ERROR, INFO, or NONE)."
  type        = string
  default     = "ERROR"
}

variable "guardrail_policy_arns" {
  description = <<-EOT
    Read-only AWS managed policy ARNs that bound what can be run from chat and
    are attached to this receiver's IAM role. Defaults to ReadOnlyAccess.

    NOTE: the aws_chatbot_slack_channel_configuration resource defaults this to
    AdministratorAccess when unset — the opposite of least privilege — so this
    module sets an explicit read-only default and you should never point it at
    a policy granting write/mutate actions.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}
