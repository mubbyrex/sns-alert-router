# integrations/codepipeline

EventBridge rules that route CodePipeline **pipeline execution** state changes
to the Phase 1 severity topics. Only EventBridge rules and targets — no SNS
topics, no IAM roles (the Phase 1 topic policy already grants
`events.amazonaws.com` publish rights), no Chatbot configuration.

## What it matches

- **Source:** `aws.codepipeline`
- **detail-type:** `CodePipeline Pipeline Execution State Change`

| Rule | `detail.state` | Routes to |
|------|----------------|-----------|
| failed | `FAILED` | `critical` |
| started-succeeded | `STARTED`, `SUCCEEDED` | `info` |

`SUPERSEDED`, `STOPPING`, `STOPPED`, `CANCELED`, `RESUMED` are **not routed**
(no rule) by default. Each rule reshapes the event into the AWS Chatbot custom
notification schema.

The **failed** message includes a deep link to the pipeline execution in the
console, built from `detail.pipeline`, `detail.execution-id`, and the event
region:

```
https://console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/executions/<execution-id>?region=<region>
```

(It's emitted as a bare, auto-linked URL rather than a `<url|label>` markdown
link, because `<...>` is the EventBridge input-transformer variable delimiter.)

## Filtering to specific pipelines

By default all pipelines are monitored. Set `pipeline_names` to restrict both
rules to specific pipelines (adds a `detail.pipeline` match to the event
pattern):

```hcl
module "pipeline_alerts" {
  source         = "../../modules/integrations/codepipeline"
  topic_arns     = module.core.topic_arns
  name_prefix    = "myapp"
  pipeline_names = ["prod-deploy", "release"]
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topic_arns` | `map(string)` | — | From `module.core.topic_arns`; must include `critical` and `info`. |
| `name_prefix` | `string` | — | Prefix for rule names, avoids collisions. |
| `pipeline_names` | `list(string)` | `[]` | Restrict to these pipelines; empty = all. |

## Outputs

| Name | Description |
|------|-------------|
| `rule_arns` | Map of logical rule name → EventBridge rule ARN. |
