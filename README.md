# sns-alert-router

A Terraform module for a **severity-tiered, noise-filtered alert routing
backbone on AWS**, delivered to Slack (and, later, Teams) via AWS Chatbot.

**What AWS already gives you natively** (this module does *not* re-implement any
of it): SNS pub/sub topics; EventBridge event-pattern matching, routing, and
`input_transformer`; CloudWatch Alarms → SNS; and AWS Chatbot delivering an SNS
topic to a Slack/Teams channel.

**What this module adds** — the judgment AWS does not: a **severity taxonomy**
(which topics exist, what "critical" means), **noise-filtering** EventBridge
patterns that exclude known-routine events, **`input_transformer` templates**
that turn raw event JSON into readable alerts, **least-privilege IAM** scoped
per use case, and a **type-agnostic receiver abstraction** that packages all of
it as reusable, composable Terraform. If a change just re-does what SNS,
EventBridge, or Chatbot already do, it doesn't belong here.

---

## Architecture

```text
[ AWS services: ECS / CodePipeline / CodeDeploy / ECR ]     [ CloudWatch Alarms,
        │                                                     direct sns:Publish ]
        ▼                                                            │
  modules/integrations/<service>                                     │
  • EventBridge rules: severity routing + noise filtering            │
  • input_transformer → Chatbot custom notification schema           │
        │                                                            │
        ▼                                                            ▼
   modules/core ───────────────────────────────────────────────────────
   • one SNS topic per severity tier (critical/warning/info)
   • least-privilege topic policy per topic
   • knows NOTHING about Slack/Teams/email
   • output: topic_arns (map: tier → ARN)
        │
        │ topic_arns consumed by however many receivers you declare
        ▼                         ▼                            ▼
  receivers/slack           receivers/email            receivers/teams
  (tested)                  (tested)                   (roadmap — not built)
```

`modules/core` only creates topics and exposes their ARNs. Every delivery
mechanism is its own small module under `modules/receivers/<type>/` sharing one
input contract: `topic_arns` + `severity_tiers` + type-specific config. You
compose as many receivers, of any types, as you want — there is no monolithic
`receivers = {...}` variable, and `modules/core` never changes when a receiver
type is added.

## Usage

Submodules are addressed with the registry's double-slash syntax
(`<namespace>/<name>/<provider>//modules/<path>`). If you consume the repo
directly from GitHub instead, the same double-slash form applies:
`github.com/mubbyrex/terraform-aws-sns-alert-router//modules/core`.

```hcl
# One core backbone: critical / warning / info SNS topics.
module "core" {
  source      = "mubbyrex/sns-alert-router/aws//modules/core"
  name_prefix = "alert-router"
}

# A Slack channel that only wants CRITICAL alerts.
module "platform_critical" {
  source = "mubbyrex/sns-alert-router/aws//modules/receivers/slack"

  configuration_name = "alert-router-platform-critical"
  topic_arns         = module.core.topic_arns
  severity_tiers     = ["critical"]
  slack_team_id      = var.slack_team_id     # your workspace ID
  slack_channel_id   = var.slack_channel_id  # the channel ID, not its name
  # guardrail_policy_arns defaults to ReadOnlyAccess (read-only from chat).
}

# An email list that wants EVERYTHING.
module "oncall_email" {
  source = "mubbyrex/sns-alert-router/aws//modules/receivers/email"

  topic_arns      = module.core.topic_arns
  severity_tiers  = ["critical", "warning", "info"]
  email_addresses = ["oncall@example.com"]
}

# An AWS-service integration: real ECS events routed by severity, with the
# noise filtering already encoded (deploy scale-downs and manual stops don't
# page anyone; real crashes do).
module "ecs_alerts" {
  source = "mubbyrex/sns-alert-router/aws//modules/integrations/ecs"

  topic_arns  = module.core.topic_arns
  name_prefix = "alert-router"
}
```

Adding a third receiver — or a whole new receiver *type* or integration — is one
more `module` block here and zero changes to `modules/core`. A runnable version
of exactly this composition lives in
[`examples/standalone/`](examples/standalone/).

## Integrations

Each integration is an independent, optional module under
`modules/integrations/<service>/` that creates **only EventBridge rules and
targets** — no topics, no IAM, no receiver knowledge. All share the same input
contract (`topic_arns` + `name_prefix` + service-specific filters) and emit the
Chatbot custom notification schema.

| Module | What it routes | Routing summary |
| ------ | -------------- | --------------- |
| [`integrations/ecs`](modules/integrations/ecs/) | ECS task stops + service deployments | Unexpected task stop (`stopCode` not excluded) → critical; deployment `ERROR` → critical; deployment in-progress → info. Deploy scale-downs and manual stops are filtered by default (`stop_code_exclusions`). |
| [`integrations/codepipeline`](modules/integrations/codepipeline/) | Pipeline execution state changes | `FAILED` → critical (with console execution deep link); `STARTED`/`SUCCEEDED` → info. Optional `pipeline_names` filter. |
| [`integrations/codedeploy`](modules/integrations/codedeploy/) | Deployment state changes | `FAILURE` → critical, `STOP` → warning (both with console deep link); `START`/`SUCCESS` → info. Optional `application_names` filter. |
| [`integrations/ecr`](modules/integrations/ecr/) | Image scan findings (basic scanning) | `CRITICAL`/`HIGH` findings → critical; `MEDIUM`-only → warning; clean/`LOW` → info — mutually exclusive, one alert per scan. Optional `repository_names` filter. |

**CloudWatch Alarms need no integration module.** A CloudWatch Alarm publishes
to SNS natively — point its `alarm_actions` at the tier ARN from
`module.core.topic_arns` and it just works, zero extra configuration. That
wiring is deliberately *not* re-built here (see the boundary note at the top of
this README).

## Gotchas (discovered during end-to-end testing)

These are real failure modes hit while getting this working end to end. Each one
fails **silently or confusingly**, so they're worth knowing before you debug.

1. **AWS Chatbot silently drops SNS messages that don't match its custom
   notification schema.** The `input_transformer` (or whatever publishes to the
   topic) must emit exactly:

   ```json
   { "version": "1.0", "source": "custom", "content": { "textType": "client-markdown", "title": "…", "description": "…" } }
   ```

   A message in any other shape is dropped by Chatbot with **no error, no log,
   nothing in the channel**. See the `input_transformer` in
   [`examples/standalone/main.tf`](examples/standalone/main.tf) for a working
   template.

2. **`put-events` must include the full event envelope to match EventBridge
   rules.** A minimal `PutEvents` entry is accepted by the API (returns a
   success `EventId`) but **does not trigger rule matching** unless it carries
   the full envelope EventBridge expects — `account`, `region`, `time`,
   `resources`. A `200` from `put-events` is *not* evidence the rule fired.

3. **`@Amazon Q` must be invited to the target Slack channel.** The AWS console's
   "send test message" button bypasses this, so testing from the console looks
   like it works — but **real SNS-delivered messages will not appear** until the
   `@Amazon Q` (AWS Chatbot) app is invited to the channel. A green console test
   is not proof delivery works.

4. **The deployment region must match the `--region` in `put-events`.**
   Resources deploy to the *provider's* region (here, `var.aws_region`), which is
   not necessarily your AWS CLI default region. If `put-events --region` points
   somewhere else, the event lands on a different bus and nothing matches — with
   no error.

5. **SNS email subscriptions stay `PendingConfirmation` until confirmed.** Each
   subscribed address gets a confirmation email it must click before any delivery
   happens. This is an AWS SNS constraint, **not a module bug** — there is no API
   to auto-confirm an email subscription.

## Current scope

- **Slack receiver — tested and working** (`modules/receivers/slack`).
- **Email receiver — tested and working** (`modules/receivers/email`).
- **Integrations — ECS, CodePipeline, CodeDeploy, ECR** — event patterns
  verified against AWS's `TestEventPattern` API; ECS wired into the runnable
  example.
- **Teams receiver — not built.** Teams uses the *same* underlying AWS Chatbot
  pattern (there is an `aws_chatbot_teams_channel_configuration` resource), so
  the abstraction already accommodates it — but it is **not implemented or tested
  in this repo yet**. It is deliberately absent (see roadmap), not stubbed.

## Roadmap

- **Phase 1 — core alert routing.** Severity-tiered SNS topics, least-privilege
  IAM, EventBridge noise-filtering example, Slack + email receivers. ✅ Done.
- **Phase 2 — CI/CD + compute integrations.** ECS, CodePipeline, CodeDeploy,
  and ECR integration modules, each independent and optional. ✅ Done.
- **Phase 3 — RDS + Lambda integrations.** Same integration-module pattern for
  RDS events and Lambda error alerting. Not started.
- **Phase 4 — Teams receiver module.** `modules/receivers/teams/` built and
  tested against the same `topic_arns` + `severity_tiers` contract, including the
  Teams-specific Adaptive Card formatting Slack doesn't require. Not started.

## Repo layout

| Path                       | What                                                                             |
| -------------------------- | -------------------------------------------------------------------------------- |
| `modules/core/`            | Severity-tiered SNS topics + least-privilege topic policies.                     |
| `modules/receivers/slack/` | One AWS Chatbot Slack channel receiver (dedicated read-only IAM role).           |
| `modules/receivers/email/` | SNS email subscriptions per subscribed tier.                                     |
| `modules/integrations/`    | Per-service EventBridge routing: `ecs/`, `codepipeline/`, `codedeploy/`, `ecr/`. |
| `examples/standalone/`     | Runnable core + both receivers + ECS integration + noise-filter example.         |

## Requirements

- Terraform `>= 1.9.0` (receiver modules use cross-variable validation).
- `hashicorp/aws >= 5.0` (developed and tested against v6.51.0).
- An AWS Chatbot ↔ Slack workspace authorization (one-time, done in the console)
  and the `AWSServiceRoleForAWSChatbot` service-linked role in the account. See
  [`examples/standalone/README.md`](examples/standalone/README.md).
