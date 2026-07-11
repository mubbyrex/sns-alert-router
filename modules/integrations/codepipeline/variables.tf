variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from module.core's topic_arns output. Must include \"critical\" and \"info\"."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix for EventBridge rule names (e.g. \"<name_prefix>-codepipeline-failed\") so multiple module instances in one account do not collide."
  type        = string
}

variable "pipeline_names" {
  description = "Specific pipeline names to monitor. Empty list (default) monitors all pipelines; non-empty adds a detail.pipeline match to every rule."
  type        = list(string)
  default     = []
}
