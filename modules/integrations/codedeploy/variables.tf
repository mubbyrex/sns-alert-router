variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from module.core's topic_arns output. Must include \"critical\", \"warning\", and \"info\"."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix for EventBridge rule names (e.g. \"<name_prefix>-codedeploy-failed\") so multiple module instances in one account do not collide."
  type        = string
}

variable "application_names" {
  description = "Specific CodeDeploy application names to monitor. Empty list (default) monitors all applications; non-empty adds a detail.application match to every rule."
  type        = list(string)
  default     = []
}
