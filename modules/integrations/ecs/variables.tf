variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from module.core's topic_arns output. Must include \"critical\" and \"info\"."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix for EventBridge rule names (e.g. \"<name_prefix>-ecs-task-stopped\") so multiple module instances in one account do not collide."
  type        = string
}

variable "stop_code_exclusions" {
  description = <<-EOT
    ECS task stopCode values excluded from the task-stopped-critical rule.
    This is the FULL exclusion list (a replacement, not an append), so the
    default is visible and fully overridable. Defaults exclude deploy-triggered
    scale-downs (ServiceSchedulerInitiated) and manual stops (UserInitiated);
    real failures (EssentialContainerExited, TaskFailedToStart) are not excluded
    and still alert. Drop ServiceSchedulerInitiated to also alert on
    health-check-driven task replacements.
  EOT
  type        = list(string)
  default     = ["ServiceSchedulerInitiated", "UserInitiated"]
}
