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

variable "email_addresses" {
  description = "Email addresses to subscribe to every subscribed tier's topic. Each address receives a confirmation email it must click to activate (see README)."
  type        = list(string)
}
