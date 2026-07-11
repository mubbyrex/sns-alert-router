# integrations/ecs

EventBridge rules that route ECS events to the Phase 1 severity topics. This
module creates only EventBridge rules and targets — no SNS topics, no IAM
roles (the Phase 1 topic policy already grants `events.amazonaws.com` publish
rights), no Chatbot configuration.

## What it matches

| Rule | Source | detail-type | Match | Routes to |
|------|--------|-------------|-------|-----------|
| task stopped | `aws.ecs` | `ECS Task State Change` | `lastStatus = STOPPED` and `stopCode` not in `stop_code_exclusions` | `critical` |
| deployment failed | `aws.ecs` | `ECS Deployment State Change` | `eventType = ERROR` | `critical` |
| deployment in progress | `aws.ecs` | `ECS Deployment State Change` | `eventType = INFO`, `eventName = SERVICE_DEPLOYMENT_IN_PROGRESS` | `info` |

Each rule reshapes the event into the AWS Chatbot custom notification schema
(`version: "1.0"`, `source: "custom"`, `content.textType: client-markdown`).

## Noise filtering — `stop_code_exclusions`

The task-stopped rule fires on any `stopCode` **except** those in
`stop_code_exclusions`. The default is the full list
`["ServiceSchedulerInitiated", "UserInitiated"]` — deploy-triggered
scale-downs and manual stops. Real failures (`EssentialContainerExited`,
`TaskFailedToStart`) are not excluded and still alert.

Because the value is the complete list (a replacement, not an append), you can
see and fully override it:

```hcl
module "ecs_alerts" {
  source      = "../../modules/integrations/ecs"
  topic_arns  = module.core.topic_arns
  name_prefix = "myapp"

  # Also suppress Spot interruptions:
  stop_code_exclusions = ["ServiceSchedulerInitiated", "UserInitiated", "SpotInterruption"]
}
```

Note that the default `ServiceSchedulerInitiated` exclusion also suppresses
health-check-driven task replacements (the service scheduler stopping a task
that failed its ELB/health checks), not just deployments — to alert on those,
remove `ServiceSchedulerInitiated` from `stop_code_exclusions`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topic_arns` | `map(string)` | — | From `module.core.topic_arns`; must include `critical` and `info`. |
| `name_prefix` | `string` | — | Prefix for rule names, avoids collisions. |
| `stop_code_exclusions` | `list(string)` | `["ServiceSchedulerInitiated","UserInitiated"]` | Full list of `stopCode` values to exclude from the task-stopped rule. |

## Outputs

| Name | Description |
|------|-------------|
| `rule_arns` | Map of logical rule name → EventBridge rule ARN. |
