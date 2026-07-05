locals {
  # Subscribe only to the topics for the requested tiers, not all of
  # topic_arns. severity_tiers is validated (in variables.tf) to be a subset of
  # topic_arns' keys, so every lookup here is guaranteed to resolve.
  subscribed_topic_arns = [for tier in var.severity_tiers : var.topic_arns[tier]]
}

# Dedicated IAM role for this receiver, trusted only by the Chatbot service
# principal confirmed in Task 3.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.configuration_name}-chatbot"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Attach the read-only guardrail policies to the role. These are the same
# policies passed to the Chatbot config as guardrails; keeping them read-only
# means nothing mutating can be run from chat.
resource "aws_iam_role_policy_attachment" "guardrails" {
  for_each = toset(var.guardrail_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_chatbot_slack_channel_configuration" "this" {
  configuration_name = var.configuration_name
  iam_role_arn       = aws_iam_role.this.arn
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  logging_level      = var.logging_level

  # Explicit read-only guardrails (never the AdministratorAccess default).
  guardrail_policy_arns = var.guardrail_policy_arns

  # Only the topics matching severity_tiers, not the whole topic_arns map.
  sns_topic_arns = local.subscribed_topic_arns
}
