# integrations/codedeploy

EventBridge rules that route CodeDeploy **deployment** state changes to the
Phase 1 severity topics. Only EventBridge rules and targets — no SNS topics, no
IAM roles (the Phase 1 topic policy already grants `events.amazonaws.com`
publish rights), no Chatbot configuration.

## What it matches

- **Source:** `aws.codedeploy`
- **detail-type:** `CodeDeploy Deployment State-change Notification`

| Rule | `detail.state` | Routes to |
|------|----------------|-----------|
| failed | `FAILURE` | `critical` |
| stopped | `STOP` | `warning` |
| started-succeeded | `START`, `SUCCESS` | `info` |

`READY` (a blue/green intermediate state) is **not routed**. Each rule reshapes
the event into the AWS Chatbot custom notification schema.

**State strings are terse, not plain English:** CodeDeploy emits `FAILURE`,
`STOP`, `START`, `SUCCESS` — *not* `FAILED`/`STOPPED`/`STARTED`/`SUCCEEDED`.
That is what appears in the Slack message's `*State:*` line.

Every message includes the **application** (`detail.application`) and
**deployment group** (`detail.deploymentGroup`) — the first thing on-call needs
to know is which app/group is affected, not just that a deployment changed
state. The **failed** and **stopped** messages additionally include a console
deep link built from `detail.deploymentId` and the event region:

```
https://console.aws.amazon.com/codesuite/codedeploy/deployments/<deployment-id>?region=<region>
```

(Emitted as a bare, auto-linked URL rather than a `<url|label>` markdown link,
because `<...>` is the EventBridge input-transformer variable delimiter.)

## Filtering to specific applications

By default all applications are monitored. Set `application_names` to restrict
every rule to specific applications (adds a `detail.application` match):

```hcl
module "codedeploy_alerts" {
  source            = "../../modules/integrations/codedeploy"
  topic_arns        = module.core.topic_arns
  name_prefix       = "myapp"
  application_names = ["web-app", "api"]
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topic_arns` | `map(string)` | — | From `module.core.topic_arns`; must include `critical`, `warning`, `info`. |
| `name_prefix` | `string` | — | Prefix for rule names, avoids collisions. |
| `application_names` | `list(string)` | `[]` | Restrict to these applications; empty = all. |

## Outputs

| Name | Description |
|------|-------------|
| `rule_arns` | Map of logical rule name → EventBridge rule ARN. |
