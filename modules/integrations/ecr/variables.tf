variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from module.core's topic_arns output. Must include \"critical\", \"warning\", and \"info\"."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix for EventBridge rule names (e.g. \"<name_prefix>-ecr-critical\") so multiple module instances in one account do not collide."
  type        = string
}

variable "repository_names" {
  description = "Specific ECR repository names to monitor. Empty list (default) monitors all repositories; non-empty adds a detail.repository-name match to every rule."
  type        = list(string)
  default     = []
}
