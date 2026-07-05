# One SNS topic per severity tier. The tier set is driven entirely by the
# severity_tiers variable (REQ-1) — adding a tier is a variable change, never
# a source change.
#
# Consumer-level tags (Project, Environment, ManagedBy, ...) are applied via
# the provider's `default_tags` in the consumer's own Terraform, not through
# module variables. The only tag the module sets itself is SeverityTier, which
# is module-specific metadata a consumer can't derive on their own.
resource "aws_sns_topic" "this" {
  for_each = var.severity_tiers

  name         = "${var.name_prefix}-${each.key}"
  display_name = each.value.display_name

  tags = {
    SeverityTier = each.key
  }
}

# Least-privilege topic policy (REQ-2): each topic accepts sns:Publish only
# from the EventBridge service principal. No wildcard principal, no broad
# publish rights. A consumer that needs a direct sns:Publish from their own
# application adds their own topic-policy statement in their own Terraform,
# referencing the ARN from the topic_arns output — the core module does not
# grant that by default.
resource "aws_sns_topic_policy" "this" {
  for_each = var.severity_tiers

  arn = aws_sns_topic.this[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.this[each.key].arn
    }]
  })
}
