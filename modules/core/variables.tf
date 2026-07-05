variable "severity_tiers" {
  description = <<-EOT
    Map of severity tier name to its configuration. Each key becomes an
    SNS topic. Default set is critical/warning/info; consumers may add
    tiers (e.g. "security") without modifying module source.
  EOT
  type = map(object({
    display_name = string
  }))
  default = {
    critical = { display_name = "Critical Alerts" }
    warning  = { display_name = "Warning Alerts" }
    info     = { display_name = "Info Alerts" }
  }
}

variable "name_prefix" {
  description = <<-EOT
    Prefix applied to every SNS topic name, combined with the severity tier
    key (e.g. "<name_prefix>-critical"). Has no default and is required so
    that multiple instances of this module in the same AWS account do not
    collide on topic names.
  EOT
  type        = string
}
