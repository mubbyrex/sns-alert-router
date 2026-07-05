# receivers/slack

A single AWS Chatbot ("Amazon Q Developer in chat applications") Slack channel
receiver for the `sns-alert-router` core module. It subscribes one Slack
channel to a chosen subset of the core module's severity-tiered SNS topics,
using a dedicated, read-only IAM role.

This module provisions **exactly one** receiver. To deliver to multiple Slack
channels (e.g. a critical-only on-call channel plus an everything channel),
declare multiple instances of this module — multiplicity is the consumer's
composition, not a variable inside the module.

## Prerequisite — Chatbot service-linked role

Before applying this module, the AWS Chatbot service-linked role
**`AWSServiceRoleForAWSChatbot`** must already exist in the target account.
AWS creates it automatically the first time you configure Chatbot/Amazon Q in
the console, or you can create it explicitly:

```bash
aws iam create-service-linked-role --aws-service-name management.chatbot.amazonaws.com
```

If this role does not exist, the first
`aws_chatbot_slack_channel_configuration` apply can fail or leave the resource
in a bad state (see hashicorp/terraform-provider-aws issue #41183). This is an
account-level prerequisite, not something this module creates — creating a
service-linked role is an account-wide, one-time action that doesn't belong to
a per-receiver module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `configuration_name` | `string` | — (required) | Unique name for this Chatbot configuration and its IAM role. Must be unique per account. |
| `topic_arns` | `map(string)` | — (required) | Map of severity tier → SNS topic ARN, from `modules/core`'s `topic_arns` output. |
| `severity_tiers` | `list(string)` | — (required) | Which keys of `topic_arns` this channel subscribes to. Must be a subset of `topic_arns`' keys. |
| `slack_team_id` | `string` | — (required) | Slack workspace ID. |
| `slack_channel_id` | `string` | — (required) | Slack channel ID (not the channel name). |
| `logging_level` | `string` | `"ERROR"` | Chatbot logging level. |
| `guardrail_policy_arns` | `list(string)` | `["arn:aws:iam::aws:policy/ReadOnlyAccess"]` | Read-only guardrail policies bounding what can be run from chat. Do not set a policy that grants write/mutate actions. |

## Output

| Name | Description |
|------|-------------|
| `chatbot_configuration_arn` | ARN of the created Chatbot Slack channel configuration. |
