# =============================================================================
# Task 1 findings — ECR Image Scan EventBridge event schema (REQ-P2-4)
# Verified against AWS docs (Amazon ECR events and EventBridge) as of
# 2026-07-06.
# -----------------------------------------------------------------------------
# EVENT SHAPE — basic scanning "ECR Image Scan":
#   source       = "aws.ecr"
#   detail-type  = "ECR Image Scan"
#   detail.scan-status            -> "COMPLETE"
#   detail.repository-name        -> string
#   detail.image-tags             -> ARRAY (may be empty [])
#   detail.finding-severity-counts -> FLAT map of severity -> integer, e.g.
#       { "CRITICAL": 10, "MEDIUM": 9 }
#
# KEY FACT: finding-severity-counts only includes a severity KEY when that
# count is > 0. If an image has no CRITICAL findings, there is NO "CRITICAL"
# key at all (not "CRITICAL": 0). This shapes the matching strategy:
#   - "has CRITICAL findings"  -> { "CRITICAL": [{ "numeric": [">", 0] }] }
#     (or equivalently { "CRITICAL": [{ "exists": true }] })
#   - "no CRITICAL/HIGH"       -> { "CRITICAL": [{ "exists": false }],
#                                    "HIGH":     [{ "exists": false }] }
# Numeric matching DOES work on the integer values of this map, and exists
# matching works because keys are absent-when-zero. So design.md's numeric
# approach is viable; "no higher severity" is expressed with exists:false
# (NOT anything-but). Severity-group routing (Task 5):
#   CRITICAL or HIGH present            -> critical topic
#   MEDIUM present, no CRITICAL/HIGH    -> warning topic
#   LOW/INFORMATIONAL present, none above -> info topic
# ("or" across two severity keys uses $or; verify the exact 3-rule patterns
# with `aws events test-event-pattern` in Task 5 — this is the highest-risk
# pattern in Phase 2.)
#
# NOTE: this is BASIC scanning. Enhanced (Inspector) scanning emits different
# events; Phase 2 targets basic-scan "ECR Image Scan" per design.md. Image
# push events ("ECR Image Action") are intentionally out of scope.
#
# Task 5 — layered routing VERIFIED with aws events test-event-pattern (each
# scan matches exactly one rule; mutually exclusive):
#   critical: finding-severity-counts has CRITICAL>0 OR HIGH>0  ($or + numeric)
#   warning : MEDIUM>0 AND CRITICAL absent AND HIGH absent      (exists:false)
#   info    : COMPLETE AND CRITICAL/HIGH/MEDIUM all absent       (exists:false)
# HIGH is included in the critical rule (per REQ-P2-4 "CRITICAL or HIGH") and
# excluded from warning/info — otherwise a HIGH-only scan would match no rule.
# exists:false works on the nested finding-severity-counts leaf keys.
#
# detail.image-digest is present on COMPLETE scans, so the console scan-results
# deep link builds from repository-name + image-digest + $.region. image-tags
# may be empty (untagged image), so the display tag can render blank; the link
# uses the digest, not the tag. A severity with zero findings has no key in the
# event, so its count renders blank in the message.
#
# EventBridge rules -> SNS need NO IAM role (Phase 1 topic policy covers it).
# =============================================================================

locals {
  tags = { Integration = "ecr" }

  # detail.repository-name match added only when repository_names is non-empty.
  repository_filter = length(var.repository_names) > 0 ? { "repository-name" = var.repository_names } : {}

  # Shared console scan-results deep link (digest-based, so reliable even for
  # untagged images). Emitted BARE — "<...>" is the input-transformer variable
  # delimiter, so Slack's <url|label> syntax cannot be used.
  console_url = "https://console.aws.amazon.com/ecr/repositories/<repository>/image/<image_digest>/scan-results?region=<region>"

  rules = {
    critical = {
      tier = "critical"
      # CRITICAL>0 OR HIGH>0
      severity_match = {
        "$or" = [
          { CRITICAL = [{ numeric = [">", 0] }] },
          { HIGH = [{ numeric = [">", 0] }] },
        ]
      }
      input_paths = {
        repository     = "$.detail.repository-name"
        image_tag      = "$.detail.image-tags[0]"
        image_digest   = "$.detail.image-digest"
        region         = "$.region"
        critical_count = "$.detail.finding-severity-counts.CRITICAL"
        high_count     = "$.detail.finding-severity-counts.HIGH"
        medium_count   = "$.detail.finding-severity-counts.MEDIUM"
      }
      title       = ":rotating_light: *CRITICAL* | ECR scan findings"
      description = "*Repository:* <repository>\\n*Image tag:* <image_tag>\\n*Findings —* Critical: <critical_count>  High: <high_count>  Medium: <medium_count>\\n*Console:* ${local.console_url}"
    }
    warning = {
      tier = "warning"
      # MEDIUM>0 AND no CRITICAL AND no HIGH
      severity_match = {
        MEDIUM   = [{ numeric = [">", 0] }]
        CRITICAL = [{ exists = false }]
        HIGH     = [{ exists = false }]
      }
      input_paths = {
        repository   = "$.detail.repository-name"
        image_tag    = "$.detail.image-tags[0]"
        image_digest = "$.detail.image-digest"
        region       = "$.region"
        medium_count = "$.detail.finding-severity-counts.MEDIUM"
      }
      title       = ":warning: *WARNING* | ECR medium-severity findings"
      description = "*Repository:* <repository>\\n*Image tag:* <image_tag>\\n*Medium findings:* <medium_count>\\n*Console:* ${local.console_url}"
    }
    info = {
      tier = "info"
      # COMPLETE AND no CRITICAL/HIGH/MEDIUM
      severity_match = {
        CRITICAL = [{ exists = false }]
        HIGH     = [{ exists = false }]
        MEDIUM   = [{ exists = false }]
      }
      input_paths = {
        repository   = "$.detail.repository-name"
        image_tag    = "$.detail.image-tags[0]"
        image_digest = "$.detail.image-digest"
        region       = "$.region"
      }
      title       = ":information_source: *INFO* | ECR scan complete"
      description = "*Repository:* <repository>\\n*Image tag:* <image_tag>\\n*Result:* no medium-or-higher findings\\n*Console:* ${local.console_url}"
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name        = "${var.name_prefix}-ecr-${each.key}"
  description = "ECR image scan findings routed to the ${each.value.tier} tier."
  tags        = local.tags

  event_pattern = jsonencode({
    source        = ["aws.ecr"]
    "detail-type" = ["ECR Image Scan"]
    detail = merge(
      {
        "scan-status"             = ["COMPLETE"]
        "finding-severity-counts" = each.value.severity_match
      },
      local.repository_filter,
    )
  })
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "${each.value.tier}-topic"
  arn       = var.topic_arns[each.value.tier]

  input_transformer {
    input_paths = each.value.input_paths

    input_template = <<-EOT
      {
        "version": "1.0",
        "source": "custom",
        "content": {
          "textType": "client-markdown",
          "title": "${each.value.title}",
          "description": "${each.value.description}",
          "keywords": ["${each.value.tier}", "ecr"]
        }
      }
    EOT
  }
}
