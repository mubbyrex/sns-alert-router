# =============================================================================
# Task 3 findings — CodePipeline EventBridge event schema (REQ-P2-2)
# Verified against AWS docs (Monitoring CodePipeline events) as of 2026-07-06.
# -----------------------------------------------------------------------------
#   source       = "aws.codepipeline"
#   detail-type  = "CodePipeline Pipeline Execution State Change"  (exact —
#       spacing/casing matter for EventBridge matching; confirmed verbatim)
#   detail.state -> FAILED | STARTED | SUCCEEDED | SUPERSEDED | STOPPING |
#       STOPPED | CANCELED | RESUMED  (only FAILED/STARTED/SUCCEEDED routed)
#   detail.pipeline      -> pipeline name
#   detail.execution-id  -> execution ID (present on pipeline-level events)
#   $.region             -> event region (top-level)
#
# EXECUTION URL (user request): the FAILED rule builds a console deep link from
# detail.pipeline + detail.execution-id + $.region — all present in the event,
# so the URL constructs cleanly. Emitted as a BARE url (Slack/Chatbot auto-links
# it); we deliberately do NOT use Slack's <url|label> syntax because "<...>" is
# the EventBridge input-transformer variable delimiter and would collide with
# the substitution.
#
# EventBridge rules -> SNS need NO IAM role (Phase 1 topic policy covers it).
# =============================================================================

locals {
  tags = { Integration = "codepipeline" }

  # detail.pipeline match added only when pipeline_names is non-empty, so the
  # default (empty) monitors all pipelines.
  pipeline_filter = length(var.pipeline_names) > 0 ? { pipeline = var.pipeline_names } : {}

  # One entry per rule. for_each over this avoids copy-paste between rules while
  # still allowing each rule its own severity tier and input_transformer (the
  # failed rule carries the execution URL; the info rule does not).
  rules = {
    failed = {
      states = ["FAILED"]
      tier   = "critical"
      input_paths = {
        pipeline     = "$.detail.pipeline"
        state        = "$.detail.state"
        execution_id = "$.detail.execution-id"
        region       = "$.region"
      }
      template = <<-EOT
        {
          "version": "1.0",
          "source": "custom",
          "content": {
            "textType": "client-markdown",
            "title": ":rotating_light: *CRITICAL* | CodePipeline failed",
            "description": "*Pipeline:* <pipeline>\n*State:* <state>\n*Execution:* <execution_id>\n*Console:* https://console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/executions/<execution_id>?region=<region>",
            "keywords": ["critical", "codepipeline"]
          }
        }
      EOT
    }
    started-succeeded = {
      states = ["STARTED", "SUCCEEDED"]
      tier   = "info"
      input_paths = {
        pipeline = "$.detail.pipeline"
        state    = "$.detail.state"
      }
      template = <<-EOT
        {
          "version": "1.0",
          "source": "custom",
          "content": {
            "textType": "client-markdown",
            "title": ":information_source: *INFO* | CodePipeline <state>",
            "description": "*Pipeline:* <pipeline>\n*State:* <state>",
            "keywords": ["info", "codepipeline"]
          }
        }
      EOT
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name        = "${var.name_prefix}-codepipeline-${each.key}"
  description = "CodePipeline pipeline execution state ${join("/", each.value.states)}."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Pipeline Execution State Change"]
    detail = merge(
      { state = each.value.states },
      local.pipeline_filter,
    )
  })
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "${each.value.tier}-topic"
  arn       = var.topic_arns[each.value.tier]

  input_transformer {
    input_paths    = each.value.input_paths
    input_template = each.value.template
  }
}
