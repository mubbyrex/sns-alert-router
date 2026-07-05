output "aws_region" {
  description = "Region the example's resources were created in (resolved from the provider)."
  # aws provider v6 deprecated data.aws_region.current.name in favour of
  # .region; using .name emits a validation warning.
  value = data.aws_region.current.region
}

output "topic_arns" {
  description = "Map of severity tier to SNS topic ARN created by module.core."
  value       = module.core.topic_arns
}
