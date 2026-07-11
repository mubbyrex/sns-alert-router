# =============================================================================
# Task 1 findings — ECS EventBridge event schema verification (REQ-P2-1)
# Verified against AWS docs (ECS task state change events, EventBridge
# comparison operators) as of 2026-07-06. Provider: hashicorp/aws >= 5.0.
# -----------------------------------------------------------------------------
# EVENT SHAPE — "ECS Task State Change":
#   source       = "aws.ecs"
#   detail-type  = "ECS Task State Change"
#   detail.lastStatus     -> e.g. "STOPPED"
#   detail.stopCode       -> ENUM (stable): TaskFailedToStart |
#       EssentialContainerExited | UserInitiated | ServiceSchedulerInitiated |
#       SpotInterruption | TerminationNotice
#   detail.stoppedReason  -> FREE-FORM string, e.g.
#       "Scaling activity initiated by (deployment ecs-svc/1234...)"  (deploy)
#       "Task stopped by user request"                                (manual)
#       "Essential container in task exited"                          (real)
#
# NOISE-FILTER APPROACH — two options compared:
#
#   (A) stoppedReason + anything-but/prefix (design.md's original approach):
#       "stoppedReason": [{ "anything-but": { "prefix":
#           "Scaling activity initiated by (deployment" } }]
#       anything-but+prefix IS supported on event-bus rules. BUT:
#       - anything-but CANNOT combine a prefix with literal strings in one
#         expression (repeating a key = last one wins). So the manual-stop
#         literal ("Task stopped by user request") and consumer-supplied
#         additional_stop_exclusions (literals) CANNOT be merged into the same
#         stoppedReason anything-but as the deploy prefix. This breaks the
#         "merge additional_stop_exclusions into the anything-but list" design.
#       - stoppedReason is free-form English; AWS can reword it and the filter
#         then silently fails (deploy stops start paging).
#
#   (B) stopCode + anything-but on the enum (RECOMMENDED):
#       "stopCode": [{ "anything-but":
#           ["ServiceSchedulerInitiated", "UserInitiated"] }]
#       - ServiceSchedulerInitiated == deploy-triggered scale-down; UserInitiated
#         == manual stop. Both excluded in ONE simple, well-supported list.
#       - EssentialContainerExited + TaskFailedToStart (real failures) still
#         match -> still alert. Matches REQ-P2-1's intent exactly.
#       - additional_stop_exclusions merges cleanly as extra stopCode enum
#         values (e.g. "SpotInterruption", "TerminationNotice" for Spot users).
#       - stopCode is a stable API enum, not free-form text -> robust.
#       TRADE-OFF: ServiceSchedulerInitiated is coarser than the deploy prefix —
#         it also covers non-deploy scheduler stops (e.g. task killed for
#         failing ELB/health checks). Those won't alert. A genuinely crashing
#         container still exits as EssentialContainerExited, so real crashes are
#         unaffected.
#
# RECOMMENDATION: adopt (B) stopCode. PENDING HUMAN CONFIRMATION to update
# design.md's ECS pattern before Task 2 writes it.
#
# DEPLOYMENT STATE events (separate rules, unaffected by the above):
#   detail-type = "ECS Deployment State Change"
#   detail.eventType ("ERROR" | "INFO"), detail.eventName
#   (e.g. SERVICE_DEPLOYMENT_FAILED / SERVICE_DEPLOYMENT_IN_PROGRESS).
#
# EventBridge rules -> SNS need NO IAM role; the Phase 1 topic policy already
# grants events.amazonaws.com publish rights.
# =============================================================================

locals {
  tags = { Integration = "ecs" }
}

# --- Rule 1: task stopped unexpectedly -> critical ---------------------------
resource "aws_cloudwatch_event_rule" "task_stopped" {
  name        = "${var.name_prefix}-ecs-task-stopped"
  description = "ECS task stopped for a non-routine reason (stopCode not in the exclusion list)."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      lastStatus = ["STOPPED"]
      stopCode   = [{ "anything-but" = var.stop_code_exclusions }]
    }
  })
}

resource "aws_cloudwatch_event_target" "task_stopped" {
  rule      = aws_cloudwatch_event_rule.task_stopped.name
  target_id = "critical-topic"
  arn       = var.topic_arns["critical"]

  input_transformer {
    input_paths = {
      cluster        = "$.detail.clusterArn"
      task_id        = "$.detail.taskArn"
      stopped_reason = "$.detail.stoppedReason"
      exit_code      = "$.detail.containers[0].exitCode"
    }

    input_template = <<-EOT
      {
        "version": "1.0",
        "source": "custom",
        "content": {
          "textType": "client-markdown",
          "title": ":rotating_light: *CRITICAL* | ECS task stopped",
          "description": "*Cluster:* <cluster>\n*Task:* <task_id>\n*Reason:* <stopped_reason>\n*Exit code:* <exit_code>",
          "keywords": ["critical", "ecs"]
        }
      }
    EOT
  }
}

# --- Rule 2: service deployment FAILED -> critical ---------------------------
resource "aws_cloudwatch_event_rule" "deployment_failed" {
  name        = "${var.name_prefix}-ecs-deployment-failed"
  description = "ECS service deployment failed (eventType ERROR)."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    detail = {
      eventType = ["ERROR"]
    }
  })
}

resource "aws_cloudwatch_event_target" "deployment_failed" {
  rule      = aws_cloudwatch_event_rule.deployment_failed.name
  target_id = "critical-topic"
  arn       = var.topic_arns["critical"]

  input_transformer {
    input_paths = {
      cluster    = "$.detail.clusterArn"
      event_name = "$.detail.eventName"
      reason     = "$.detail.reason"
    }

    input_template = <<-EOT
      {
        "version": "1.0",
        "source": "custom",
        "content": {
          "textType": "client-markdown",
          "title": ":rotating_light: *CRITICAL* | ECS deployment failed",
          "description": "*Cluster:* <cluster>\n*Event:* <event_name>\n*Reason:* <reason>",
          "keywords": ["critical", "ecs"]
        }
      }
    EOT
  }
}

# --- Rule 3: service deployment IN_PROGRESS -> info --------------------------
resource "aws_cloudwatch_event_rule" "deployment_in_progress" {
  name        = "${var.name_prefix}-ecs-deployment-in-progress"
  description = "ECS service deployment started (SERVICE_DEPLOYMENT_IN_PROGRESS)."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    detail = {
      eventType = ["INFO"]
      eventName = ["SERVICE_DEPLOYMENT_IN_PROGRESS"]
    }
  })
}

resource "aws_cloudwatch_event_target" "deployment_in_progress" {
  rule      = aws_cloudwatch_event_rule.deployment_in_progress.name
  target_id = "info-topic"
  arn       = var.topic_arns["info"]

  input_transformer {
    input_paths = {
      cluster    = "$.detail.clusterArn"
      event_name = "$.detail.eventName"
      reason     = "$.detail.reason"
    }

    input_template = <<-EOT
      {
        "version": "1.0",
        "source": "custom",
        "content": {
          "textType": "client-markdown",
          "title": ":information_source: *INFO* | ECS deployment in progress",
          "description": "*Cluster:* <cluster>\n*Event:* <event_name>\n*Reason:* <reason>",
          "keywords": ["info", "ecs"]
        }
      }
    EOT
  }
}
