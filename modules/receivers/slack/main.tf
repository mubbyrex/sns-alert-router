# =============================================================================
# Task 3 findings — AWS Chatbot resource naming verification (REQ-3)
# -----------------------------------------------------------------------------
# Verified against: hashicorp/aws v6.51.0 (the version this repo's lockfile
# pins, `terraform providers schema -json`) and cross-checked against the
# latest Terraform Registry + AWS docs as of 2026-07-03.
#
# RESOURCE NAME — still current, NOT renamed despite the AWS Chatbot ->
#   "Amazon Q Developer in chat applications" rebrand:
#     aws_chatbot_slack_channel_configuration
#   (A sibling aws_chatbot_teams_channel_configuration also exists; that is
#    Phase 3's concern, not built here.)
#
# ARGUMENTS (from the v6.51.0 provider schema):
#   Required:
#     - configuration_name  (string)
#     - iam_role_arn         (string)  -> the dedicated role this module creates
#     - slack_channel_id     (string)
#     - slack_team_id        (string)
#   Optional:
#     - sns_topic_arns       (set(string))  -> subscribe the filtered subset here
#     - guardrail_policy_arns(list(string))  -> SEE SECURITY NOTE BELOW
#     - logging_level        (string, default "ERROR")
#     - user_authorization_required (bool)
#     - region               (string)
#     - tags                 (map(string))
#   Computed (outputs):
#     - chat_configuration_arn, slack_channel_name, slack_team_name, tags_all
#
# IAM TRUST PRINCIPAL — unchanged post-rebrand, confirmed still correct:
#     chatbot.amazonaws.com   (trusted via sts:AssumeRole)
#
# SECURITY NOTE (affects Task 4, REQ-3's read-only guardrail requirement):
#   guardrail_policy_arns defaults to AWS-managed **AdministratorAccess** when
#   omitted. That is the opposite of the read-only guardrail REQ-3 mandates.
#   Task 4 MUST set guardrail_policy_arns explicitly to a read-only managed
#   policy set (e.g. arn:aws:iam::aws:policy/ReadOnlyAccess, or the tighter
#   CloudWatchReadOnlyAccess) and must NOT fall back to the provider default.
#
# OPERATIONAL NOTE:
#   The configuration expects the Chatbot service-linked role
#   (AWSServiceRoleForAWSChatbot) to already exist in the account; if it does
#   not, first-time applies can leave the resource in a bad state
#   (terraform-provider-aws issue #41183). This is an apply-time account
#   prerequisite, not a module-code change.
# =============================================================================

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
