# Resolved region of the configured provider, for any place that needs to
# reference the region without hardcoding it. (The provider block itself can't
# consume this — a provider can't derive its own region from a data source that
# depends on the provider — so the region it runs in still comes from
# var.aws_region.)
data "aws_region" "current" {}

# Core backbone: one SNS topic per severity tier (critical/warning/info).
module "core" {
  source = "../../modules/core"

  name_prefix = var.name_prefix
  # severity_tiers left at the module default: critical / warning / info.
}

# Receiver #1 — Slack, subscribed to CRITICAL ONLY. Demonstrates a receiver
# that takes a strict severity subset: only critical events reach this channel.
module "platform_critical" {
  source = "../../modules/receivers/slack"

  configuration_name = "${var.name_prefix}-platform-critical"
  topic_arns         = module.core.topic_arns
  severity_tiers     = ["critical"]
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  # guardrail_policy_arns + logging_level left at module defaults (ReadOnlyAccess / ERROR).
}

# Receiver #2 — email, subscribed to ALL tiers. Demonstrates a second receiver
# of a completely different delivery type, taking a different severity subset —
# proving the type-agnostic, multi-receiver composition (REQ-6) at the consumer
# layer with plain module blocks, no monolithic receivers variable.
module "oncall_email" {
  source = "../../modules/receivers/email"

  topic_arns      = module.core.topic_arns
  severity_tiers  = ["critical", "warning", "info"]
  email_addresses = var.oncall_email_addresses
}

# =============================================================================
# Noise-filtering EventBridge rule (REQ-4)
# -----------------------------------------------------------------------------
# WHY THIS EXISTS. Not every event that matches a source is worth paging a
# human about. A large share of "task stopped", "deployment changed", "instance
# terminated"-style events are the *expected* result of routine, self-inflicted
# activity: a scheduled job running, an operator deliberately taking an action,
# an autoscaler doing its job. Routing those to a critical channel trains people
# to ignore the channel — the classic alert-fatigue failure mode. The value this
# module adds over raw SNS+EventBridge is precisely this judgment: which
# variants of an event are signal and which are noise.
#
# WHY anything-but (and not a positive match). We want "critical UNLESS this was
# routine". Enumerating every genuinely-critical trigger value is a losing game:
# the list is open-ended and unknown triggers would silently fall through and
# never alert. The safer default is to alert on everything EXCEPT a small,
# well-understood allow-list of known-routine causes. anything-but expresses
# exactly that: match when detail.trigger is present and is NOT one of the
# excluded values. A new, never-before-seen trigger therefore still pages
# someone — failing loud, not silent, which is the correct bias for a critical
# tier. (Caveat worth knowing: anything-but only matches when the field is
# present; events omitting detail.trigger will not match this rule, so emitters
# are expected to always set it.)
#
# This uses a custom event source (com.sns-alert-router.example) rather than a
# real AWS service event on purpose: it makes the demo intent unambiguous and
# lets the pattern be exercised with a hand-published PutEvents call, without
# provisioning any real AWS service to emit events.
# =============================================================================
resource "aws_cloudwatch_event_rule" "example_critical" {
  name        = "alert-router-example-critical"
  description = "Example: route custom critical events to the critical SNS topic, excluding known-routine triggers (noise filtering)."

  event_pattern = jsonencode({
    source = ["com.sns-alert-router.example"]
    detail = {
      # Match any trigger EXCEPT the known-routine ones. See comment above.
      trigger = [{ "anything-but" = ["scheduled", "user_initiated"] }]
    }
  })
}

# Deliver matched events to the critical topic, reshaped by input_transformer
# into the AWS Chatbot *custom notification* schema so the message renders as a
# formatted card in Slack rather than raw JSON. The outer
# version/source="custom"/content envelope is Chatbot's fixed format; the values
# inside (severity/detail-type/source/trigger/description) are pulled live from
# the event via the input paths below — none of them are hardcoded.
#
# Note on variable names: EventBridge input-path VARIABLE names are plain
# alphanumeric/underscore tokens (e.g. detail_type), even though the JSON PATHS
# they map to may contain dots and dashes ($.detail-type, $.detail.trigger). A
# dotted variable name like <detail.trigger> is not reliably substituted, so we
# use clean names that produce the identical output.
resource "aws_cloudwatch_event_target" "example_critical_to_sns" {
  rule      = aws_cloudwatch_event_rule.example_critical.name
  target_id = "critical-sns-topic"
  arn       = module.core.topic_arns["critical"]

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      source      = "$.source"
      detail_type = "$.detail-type"
      trigger     = "$.detail.trigger"
      description = "$.detail.description"
    }

    # AWS Chatbot custom notification schema (client-markdown).
    input_template = <<-EOT
      {
        "version": "1.0",
        "source": "custom",
        "content": {
          "textType": "client-markdown",
          "title": ":rotating_light: *<severity>* | <detail_type>",
          "description": "*Source:* <source>\n*Trigger:* <trigger>\n*Description:* <description>",
          "keywords": ["<severity>"]
        }
      }
    EOT
  }
}
