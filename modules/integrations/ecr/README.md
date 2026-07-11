# integrations/ecr

EventBridge rules that route **ECR basic image-scan findings** to the Phase 1
severity topics by finding severity. Only EventBridge rules and targets — no SNS
topics, no IAM roles (the Phase 1 topic policy already grants
`events.amazonaws.com` publish rights), no Chatbot configuration.

## What it matches

- **Source:** `aws.ecr`
- **detail-type:** `ECR Image Scan` (basic scanning; completed scans only,
  `scan-status = COMPLETE`)

| Rule | Matches (on `finding-severity-counts`) | Routes to |
|------|----------------------------------------|-----------|
| critical | `CRITICAL > 0` **or** `HIGH > 0` | `critical` |
| warning | `MEDIUM > 0` **and** no `CRITICAL`, no `HIGH` | `warning` |
| info | scan `COMPLETE` and no `CRITICAL`/`HIGH`/`MEDIUM` | `info` |

### Why the rules look layered

ECR omits a severity key entirely when its count is zero (there is no
`"CRITICAL": 0` — the key is simply absent). So "has critical findings" is a
`numeric > 0` (or `exists: true`) match, and "no critical findings" is
`exists: false`. The warning and info rules use `exists: false` on the higher
severities so a scan with, say, both `CRITICAL` and `MEDIUM` findings matches
**only** the critical rule, never two rules at once. `HIGH` is grouped with
`CRITICAL` (per the severity mapping), so a HIGH-only scan still routes to
critical rather than falling through unmatched. This layering was verified with
`aws events test-event-pattern` — each scan matches exactly one rule.

`LOW` / `INFORMATIONAL`-only scans (and clean scans) route to `info`.

## Message content

Each message includes the repository, image tag, and a console **scan-results**
deep link built from the repository name, image digest, and region:

```
https://console.aws.amazon.com/ecr/repositories/<repository>/image/<image-digest>/scan-results?region=<region>
```

The link uses the image **digest** (always present on a completed scan), so it
works even for untagged images — in which case the displayed image tag renders
blank. The critical message shows the Critical/High/Medium finding counts; a
severity with zero findings has no key in the event, so its count renders blank.

(The URL is emitted as a bare, auto-linked URL rather than a `<url|label>`
markdown link, because `<...>` is the EventBridge input-transformer variable
delimiter.)

## Scope

Image **push** events are intentionally not included — deployment tracking is
already covered by the CodePipeline/CodeDeploy integrations, and push events add
no security signal. This is a deliberate scope decision, not a gap. Enhanced
(Amazon Inspector) scanning emits a different event shape and is not handled
here; this module targets **basic** scanning's `ECR Image Scan` event.

## Filtering to specific repositories

By default all repositories are monitored. Set `repository_names` to restrict
every rule (adds a `detail.repository-name` match):

```hcl
module "ecr_alerts" {
  source           = "../../modules/integrations/ecr"
  topic_arns       = module.core.topic_arns
  name_prefix      = "myapp"
  repository_names = ["web-app", "api"]
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topic_arns` | `map(string)` | — | From `module.core.topic_arns`; must include `critical`, `warning`, `info`. |
| `name_prefix` | `string` | — | Prefix for rule names, avoids collisions. |
| `repository_names` | `list(string)` | `[]` | Restrict to these repositories; empty = all. |

## Outputs

| Name | Description |
|------|-------------|
| `rule_arns` | Map of logical rule name → EventBridge rule ARN. |
