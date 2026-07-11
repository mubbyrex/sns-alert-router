# Standalone example

A complete, applyable example that wires `modules/core` with two different
receiver types — standalone, with no ECS, CodePipeline, or any other
service-specific dependency. A hand-published synthetic event is the only event
source.

## What this example proves

1. **Standalone usability (REQ-5).** A consumer who just wants severity-tiered
   alert routing can get value from `modules/core` plus receiver modules alone —
   nothing service-specific required. The only event source here is a manual
   `put-events` call.
2. **Multi-receiver, multi-type, severity-subset composition (REQ-6).** Two
   receivers of *different* delivery types, each subscribed to a *different*
   subset of tiers, composed with plain `module` blocks in this root — no
   monolithic `receivers = {...}` variable, no `type` discriminator:
   - `module.platform_critical` — Slack, subscribed to **`["critical"]`** only.
   - `module.oncall_email` — email, subscribed to **all three tiers**.

   Adding a third receiver (or a third type) later is one more `module` block
   here and zero changes to `modules/core`.

## What gets created

- Core: 3 SNS topics (`critical` / `warning` / `info`) + their least-privilege
  topic policies.
- Slack receiver: one Chatbot Slack channel config + a dedicated read-only IAM
  role, subscribed to the critical topic only.
- Email receiver: SNS email subscriptions (one per address) on all three topics.
- EventBridge: a noise-filtering rule (custom source
  `com.sns-alert-router.example`, `anything-but` excluding routine triggers)
  that reshapes matched events and publishes them to the critical topic.

## Prerequisites

- **AWS credentials** for the target account, with permission to create SNS,
  IAM, EventBridge, and Chatbot resources. Set the region via `aws_region`
  (default `us-east-1`).
- **A Slack workspace connected to AWS Chatbot / Amazon Q Developer in chat
  applications.** This one-time authorization is done in the AWS console
  (Amazon Q Developer in chat applications → configure a Slack client) and
  cannot be done in Terraform. It's what makes `slack_team_id` valid.
- **The `AWSServiceRoleForAWSChatbot` service-linked role must already exist in
  the account** — see the "Chatbot service-linked role" note at the bottom of
  this file. Without it, the first Slack config apply can fail.

## Usage

### 1. Provide your values

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — replace the placeholder Slack IDs and email with real
# values. terraform.tfvars is gitignored; the .example file is the committed one.
```

Each line in `terraform.tfvars.example` has a comment explaining exactly where
to find that value.

### 2. Apply

```bash
terraform init
terraform plan     # review
terraform apply
```

After apply, **confirm the email subscriptions**: each address in
`oncall_email_addresses` receives one confirmation email per subscribed tier
(three, for the default all-tiers subscription). Click the confirmation link in
each — until then, email delivery does not work. This is an AWS SNS constraint,
not a module bug (see `modules/receivers/email/README.md`).

### 3. Trigger a synthetic test event

Publish a critical-looking event that should NOT be filtered (its `trigger` is
not one of the routine values the rule excludes):

```bash
aws events put-events --entries '[
  {
    "Source": "com.sns-alert-router.example",
    "DetailType": "example.alert",
    "Detail": "{\"severity\":\"critical\",\"trigger\":\"threshold_breached\",\"description\":\"connection pool at 100% for 5m\"}"
  }
]'
```

The `input_transformer` reshapes this into AWS Chatbot's custom-notification
schema, pulling `severity` and `trigger`/`description` from `detail`, `source`
from the event `source`, and the title suffix from the event's `DetailType`
(`detail-type`). Make sure the event carries `detail.severity` — an input path
that matches nothing is silently dropped, so an event without it renders a
blank severity.

To see the **noise filter** in action, publish a routine event and confirm it
is dropped (no Slack message, no email):

```bash
aws events put-events --entries '[
  {
    "Source": "com.sns-alert-router.example",
    "DetailType": "example.alert",
    "Detail": "{\"severity\":\"critical\",\"trigger\":\"scheduled\",\"description\":\"routine, should be filtered\"}"
  }
]'
```

### 4. Test the ECS integration (Phase 2)

The `ecs_alerts` module adds a task-stopped rule that routes to the **critical**
topic while filtering out routine stops (deploy scale-downs, manual stops) by
`stopCode`. The two events below are the canonical shapes; both were verified
against the rule with `aws events test-event-pattern` (payload 1 matches,
payload 2 is filtered).

**Payload 1 — should alert (task stopped unexpectedly):**

```json
{
  "source": "aws.ecs",
  "detail-type": "ECS Task State Change",
  "detail": {
    "lastStatus": "STOPPED",
    "stopCode": "EssentialContainerExited",
    "stoppedReason": "Essential container in task exited",
    "clusterArn": "arn:aws:ecs:us-east-1:123456789012:cluster/example",
    "taskArn": "arn:aws:ecs:us-east-1:123456789012:task/example/abc123",
    "containers": [{"exitCode": 1}]
  }
}
```

**Payload 2 — should be filtered (deploy-triggered stop):**

```json
{
  "source": "aws.ecs",
  "detail-type": "ECS Task State Change",
  "detail": {
    "lastStatus": "STOPPED",
    "stopCode": "ServiceSchedulerInitiated",
    "stoppedReason": "Scaling activity initiated by (deployment abc123)",
    "clusterArn": "arn:aws:ecs:us-east-1:123456789012:cluster/example",
    "taskArn": "arn:aws:ecs:us-east-1:123456789012:task/example/def456",
    "containers": [{"exitCode": 0}]
  }
}
```

Verify the rule logic (this is what confirms routing, and it needs no
infrastructure) — save a payload to `event.json` and run:

```bash
aws events test-event-pattern \
  --event-pattern '{"source":["aws.ecs"],"detail-type":["ECS Task State Change"],"detail":{"lastStatus":["STOPPED"],"stopCode":[{"anything-but":["ServiceSchedulerInitiated","UserInitiated"]}]}}' \
  --event "$(cat event.json)"
# Payload 1 -> "Result": true    Payload 2 -> "Result": false
```

> **Why not `put-events` for this one?** EventBridge reserves the `aws.` source
> prefix for genuine AWS service events. A `put-events` call with
> `"Source": "aws.ecs"` is **accepted by the API (returns an `EventId`) but is
> not delivered to your rules** — you cannot spoof an `aws.ecs` event. So a real
> end-to-end test of this rule requires an **actual ECS task stop** (or, for a
> dry run, temporarily point a copy of the rule at a custom source like
> `com.sns-alert-router.example`). The `test-event-pattern` check above is the
> reliable way to confirm the routing without real ECS.

## What to expect

| Event                                       | Slack (`platform_critical`, critical-only) | Email (`oncall_email`, all tiers) |
| ------------------------------------------- | ------------------------------------------ | --------------------------------- |
| `trigger: threshold_breached` (critical)    | delivered                                  | delivered (once confirmed)        |
| `trigger: scheduled` / `user_initiated`     | filtered out                               | filtered out                      |
| ECS task stopped, `EssentialContainerExited`| delivered (critical)                       | delivered (once confirmed)        |
| ECS task stopped, `ServiceSchedulerInitiated`| filtered out                              | filtered out                      |

The Slack channel only ever sees critical events (it subscribes to the critical
topic only). Email sees any severity routed to any of the three topics. Routine
triggers are excluded by the `anything-but` filter before they reach either.

> Note: this example's EventBridge rule only publishes to the **critical**
> topic, so warning/info delivery is exercised by publishing directly to those
> topics (e.g. `aws sns publish --topic-arn <warning-arn> ...`) — the routing
> and subscriptions for all three tiers are in place regardless.

## Prerequisite — Chatbot service-linked role

Before `terraform apply`, the Chatbot service-linked role
**`AWSServiceRoleForAWSChatbot`** must already exist in the target account. AWS
creates it automatically the first time you configure Chatbot in the console, or
create it explicitly:

```bash
aws iam create-service-linked-role --aws-service-name management.chatbot.amazonaws.com
```

Without it, the first apply of the Slack channel configuration can fail or leave
the resource in a bad state (hashicorp/terraform-provider-aws issue #41183).
This is a one-time, account-level action, not something the example's Terraform
creates for you.
