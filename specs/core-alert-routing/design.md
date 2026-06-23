# Design — Phase 1: Core Alert Routing

This document covers *how* Phase 1 is built and *why*, against the
requirements in `requirements.md`. Read that file first, especially REQ-6 —
this design is built around it, and doesn't re-justify it from scratch.

## Architecture overview

```
[Any event source: CloudWatch Alarm, EventBridge rule target,
 or a direct sns:Publish call from anything with IAM permission]
        │
        ▼
┌────────────────────────────────────────────────┐
│ modules/core                                    │
│   SNS topics, one per severity tier             │
│   (critical / warning / info, configurable)     │
│   topic policies — who can publish, per topic   │
│                                                  │
│   knows NOTHING about Slack, Teams, email, or    │
│   any other delivery mechanism                  │
│                                                  │
│   output: topic_arns (map: tier name → ARN)     │
└──────────────────┬───────────────────────────────┘
                    │ topic_arns consumed by however many
                    │ receiver module instances the consumer declares
        ┌───────────┼────────────────┬─────────────────
        ▼                            ▼                 ▼
┌─────────────────┐        ┌──────────────────┐   ┌──────────────────┐
│ receivers/slack  │        │ receivers/email  │   │ receivers/teams  │
│ (Phase 1, tested) │        │ (Phase 1, tested) │   │ (Phase 3 — does  │
│                   │        │                   │   │  not exist yet)  │
│ in: topic_arns,   │        │ in: topic_arns,   │   │                  │
│  severity_tiers,  │        │  severity_tiers,  │   │ same input shape │
│  slack_team_id,   │        │  email_addresses  │   │ when it lands    │
│  slack_channel_id │        │                   │   │                  │
└─────────────────┘        └──────────────────┘   └──────────────────┘
```

Each receiver module is independent. A consumer can declare zero, one, or
many instances of each, in any combination — "two Slack channels and one
email list" is just three `module` blocks in the consumer's own Terraform,
not a configuration option inside one module.

## Why per-type modules, not one module with a `type` discriminator

This was an explicit decision, not a default — worth recording why, since
it's the kind of thing that looks over-engineered until you hit the
alternative's failure mode.

A single `modules/receivers` with a `type` field and `if/else`-style
`dynamic` blocks per type *looks* simpler at first (one module to document,
one set of docs to read) but degrades badly:
- Every new type touches the same file, growing a single module's
  complexity indefinitely and risking regressions in existing types.
- Variables end up a union of every type's needs
  (`slack_team_id`, `teams_tenant_id`, ...), all `optional()`, with no
  compile-time way to express "these three are required together if
  `type == "slack"`." Terraform's validation for that is awkward at best.
- A consumer reading the module's variables can't tell which fields apply
  to which type without reading the source.

Per-type modules avoid all of this: each module's variables are exactly
what that type needs, required (not optional-with-runtime-checks), and
adding a new type is strictly additive — a new directory, never a diff to
an existing one. The cost is more files and a small amount of repeated
structure (every receiver module takes `topic_arns` + `severity_tiers`),
which is a reasonable trade for the isolation.

## Severity taxonomy (REQ-1) — unchanged from the core's perspective

Three default tiers: `critical`, `warning`, `info`, as a variable:

```hcl
# modules/core/variables.tf
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
```

```hcl
# modules/core/outputs.tf
output "topic_arns" {
  description = "Map of severity tier name to its SNS topic ARN. Consumed by receiver modules."
  value       = { for k, v in aws_sns_topic.this : k => v.arn }
}
```

**Why topic-per-severity, not one topic with message-attribute filtering:**
topic-per-severity makes the receiver model trivial — a receiver module
just subscribes to the topic ARNs matching the tiers it cares about, no
filter-policy syntax to maintain or silently misconfigure. This is
unaffected by the REQ-6 redesign; the reasoning from the original draft
still holds.

## IAM boundary (REQ-2) — lives entirely in `modules/core`

```hcl
resource "aws_sns_topic_policy" "this" {
  for_each = var.severity_tiers
  arn      = aws_sns_topic.this[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.this[each.key].arn
    }]
  })
}
```

`modules/core` only grants publish rights, scoped per-topic, to
`events.amazonaws.com` by default. A consumer wiring a direct
`sns:Publish` from their own application must explicitly extend this
policy (or, cleaner, add their own topic policy statement in their own
Terraform referencing the topic ARN from `topic_arns`) — the core module
doesn't grant broad publish rights by default, and receiver modules never
touch publish permissions at all (they only *subscribe*, a different IAM
surface).

## `modules/receivers/slack` (REQ-3)

Takes the topic ARNs and a chosen subset of tiers, provisions one Chatbot
Slack configuration:

```hcl
# modules/receivers/slack/variables.tf
variable "topic_arns" {
  description = "Map of severity tier name to SNS topic ARN, from modules.core.topic_arns."
  type        = map(string)
}

variable "severity_tiers" {
  description = "Which keys of topic_arns this receiver subscribes to. Must be a subset of topic_arns' keys."
  type        = list(string)
}

variable "slack_team_id" {
  description = "Slack workspace ID. Find this in Slack under workspace settings, or via the AWS Chatbot console's 'Configure new client' flow."
  type        = string
}

variable "slack_channel_id" {
  description = "Slack channel ID (not the channel name) to receive alerts."
  type        = string
}

variable "logging_level" {
  type    = string
  default = "ERROR"
}

variable "guardrail_policy_arns" {
  description = "Read-only AWS-managed policy ARNs attached to the Chatbot IAM role. Defaults to a minimal read-only set."
  type        = list(string)
  default     = [] # finalized during implementation against current AWS-managed policy ARNs
}
```

A consumer wanting two Slack channels (e.g. critical-only + everything)
declares two instances of this module with different `severity_tiers` and
`slack_channel_id` values — there is no internal loop or map inside this
module for multiple channels; multiplicity is the consumer's composition,
not this module's responsibility. This is the direct resolution of the
original ask ("a map of receivers") at the composition layer rather than
inside a single module.

**Verify before implementing:** confirm the current resource name (likely
still `aws_chatbot_slack_channel_configuration`, but check given the
Chatbot → Amazon Q Developer in chat applications rebrand) and the current
Chatbot service principal against the `hashicorp/aws` provider's latest
docs — do not assume the source material's naming is still current.

## `modules/receivers/email` (REQ-6's second proof point)

Deliberately almost trivial — that's the point, it proves the abstraction
works for a delivery mechanism that has nothing to do with chat apps:

```hcl
# modules/receivers/email/variables.tf
variable "topic_arns" {
  type = map(string)
}
variable "severity_tiers" {
  type = list(string)
}
variable "email_addresses" {
  type = list(string)
}
```

```hcl
# modules/receivers/email/main.tf
resource "aws_sns_topic_subscription" "this" {
  for_each  = toset([for pair in setproduct(var.severity_tiers, var.email_addresses) : "${pair[0]}|${pair[1]}"])
  topic_arn = var.topic_arns[split("|", each.value)[0]]
  protocol  = "email"
  endpoint  = split("|", each.value)[1]
}
```

(Exact implementation of the cross-product subscription may be cleaner
with a `for` expression building a list of objects rather than the
string-split approach above — this is illustrative of the shape, not
prescriptive; Claude Code should pick whichever is more idiomatic at
implementation time.)

Note: SNS email subscriptions require manual confirmation (the subscriber
clicks a link in a confirmation email) — this is an AWS SNS constraint, not
something this module can or should automate around. Document it in the
module's README so it's not mistaken for a bug.

## `modules/receivers/teams` — explicitly does not exist in Phase 1

Reserved name, reserved shape (same `topic_arns` + `severity_tiers` input
contract as the others), zero files. Building it is Phase 3's job, and
Phase 3's `design.md` will detail the Teams-specific configuration
variables and the formatting gotcha you identified (Teams' default
Adaptive Card rendering via Chatbot needs custom formatting work that
Slack doesn't require).

## EventBridge example pattern with noise filtering (REQ-4) — unaffected
by the REQ-6 redesign

This lives at the example/pattern-reference level, independent of which
receiver modules exist, and is unchanged from the original design: one
worked example demonstrating an `anything-but` exclusion technique and an
`input_transformer` reshaping a raw event into a clean payload. As noted in
requirements.md, this demonstrates the *technique* honestly — not a
reconstruction of an unrecoverable original production rule.

## Standalone consumability (REQ-5) — now demonstrates REQ-6 too

`examples/standalone/` composes:
- One `modules/core` instance.
- One `modules/receivers/slack` instance, subscribed to `["critical"]` only.
- One `modules/receivers/email` instance, subscribed to
  `["critical", "warning", "info"]`.
- The EventBridge pattern example from REQ-4, publishing to the topics.

Applying this example and triggering the synthetic pattern should produce:
a Slack message only for critical-severity test events, and an email for
any severity. This proves both standalone usability (REQ-5) and the
multi-receiver, multi-type, severity-subset composition (REQ-6) with a
single real, applyable example — not just claims in prose.

## Explicit non-goals (restating for implementation clarity)

- No Lambda for formatting/routing.
- No custom DSL or config abstraction beyond Terraform variables and module
  composition.
- No ECS, CodePipeline, or other service-specific resources anywhere in
  Phase 1.
- No `modules/receivers/teams/` directory yet.
- No single monolithic receivers module with a type discriminator — see
  "Why per-type modules" above.
