# =============================================================================
# Task 1 findings — CodeDeploy EventBridge event schema (REQ-P2-3)
# Verified against AWS docs (CodeDeploy CloudWatch/EventBridge events, AWS
# CodeDeploy events reference) as of 2026-07-06.
# -----------------------------------------------------------------------------
# EVENT SHAPE — "CodeDeploy Deployment State-change Notification":
#   source       = "aws.codedeploy"
#   detail-type  = "CodeDeploy Deployment State-change Notification"
#   detail.state -> ENUM: FAILURE | READY | START | STOP | SUCCESS
#       (NOTE: these are the terse forms — NOT FAILED/STARTED/STOPPED/SUCCEEDED.
#        READY is a blue/green-only intermediate state, not routed here.)
#   detail.application       -> application name (string)
#   detail.deploymentGroup   -> deployment group name (string)
#   detail.deploymentId      -> deployment id (string)
#
# Severity routing (Task 4) — confirmed strings match design.md:
#   FAILURE           -> critical topic
#   STOP              -> warning topic  (manually stopped, possibly intentional)
#   START | SUCCESS   -> info topic
#   READY             -> not routed (no rule)
#
# There is also a sibling "CodeDeploy Instance State-change Notification"
# detail-type — NOT used here; this module is deployment-level only.
#
# Task 4 note — the event fields are `application` and `deploymentGroup` (NOT
# applicationName/deploymentGroupName). detail.deploymentId + $.region are both
# present, so the failed/stopped rules build a console deep link. The URL is
# emitted BARE (Chatbot auto-links it) because "<...>" is the input-transformer
# variable delimiter and collides with Slack's <url|label> syntax.
#
# EventBridge rules -> SNS need NO IAM role (Phase 1 topic policy covers it).
# =============================================================================

locals {
  tags = { Integration = "codedeploy" }

  # detail.application match added only when application_names is non-empty.
  application_filter = length(var.application_names) > 0 ? { application = var.application_names } : {}

  # One entry per rule; for_each over this keeps the three rules DRY while
  # letting each carry its own tier and input_transformer (failed/stopped
  # include the console URL; started/succeeded do not).
  paths_with_url = {
    application      = "$.detail.application"
    deployment_group = "$.detail.deploymentGroup"
    deployment_id    = "$.detail.deploymentId"
    state            = "$.detail.state"
    region           = "$.region"
  }

  rules = {
    failed = {
      states      = ["FAILURE"]
      tier        = "critical"
      input_paths = local.paths_with_url
      template    = <<-EOT
        {
          "version": "1.0",
          "source": "custom",
          "content": {
            "textType": "client-markdown",
            "title": ":rotating_light: *CRITICAL* | CodeDeploy failed",
            "description": "*Application:* <application>\n*Deployment group:* <deployment_group>\n*Deployment:* <deployment_id>\n*State:* <state>\n*Console:* https://console.aws.amazon.com/codesuite/codedeploy/deployments/<deployment_id>?region=<region>",
            "keywords": ["critical", "codedeploy"]
          }
        }
      EOT
    }
    stopped = {
      states      = ["STOP"]
      tier        = "warning"
      input_paths = local.paths_with_url
      template    = <<-EOT
        {
          "version": "1.0",
          "source": "custom",
          "content": {
            "textType": "client-markdown",
            "title": ":warning: *WARNING* | CodeDeploy stopped",
            "description": "*Application:* <application>\n*Deployment group:* <deployment_group>\n*Deployment:* <deployment_id>\n*State:* <state>\n*Console:* https://console.aws.amazon.com/codesuite/codedeploy/deployments/<deployment_id>?region=<region>",
            "keywords": ["warning", "codedeploy"]
          }
        }
      EOT
    }
    started-succeeded = {
      states = ["START", "SUCCESS"]
      tier   = "info"
      input_paths = {
        application      = "$.detail.application"
        deployment_group = "$.detail.deploymentGroup"
        state            = "$.detail.state"
      }
      template = <<-EOT
        {
          "version": "1.0",
          "source": "custom",
          "content": {
            "textType": "client-markdown",
            "title": ":information_source: *INFO* | CodeDeploy <state>",
            "description": "*Application:* <application>\n*Deployment group:* <deployment_group>\n*State:* <state>",
            "keywords": ["info", "codedeploy"]
          }
        }
      EOT
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name        = "${var.name_prefix}-codedeploy-${each.key}"
  description = "CodeDeploy deployment state ${join("/", each.value.states)}."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.codedeploy"]
    "detail-type" = ["CodeDeploy Deployment State-change Notification"]
    detail = merge(
      { state = each.value.states },
      local.application_filter,
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
