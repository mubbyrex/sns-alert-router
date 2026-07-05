# receivers/email

A trivial receiver that subscribes one or more email addresses to a chosen
subset of the core module's severity-tiered SNS topics. It exists to prove the
receiver abstraction (`topic_arns` + `severity_tiers` + type-specific config)
holds for a delivery mechanism that has nothing to do with chat apps — not
because email routing itself is complex.

It creates one `aws_sns_topic_subscription` (protocol `email`) for every
combination of subscribed tier and address.

## Manual confirmation required (not a bug)

SNS email subscriptions are **not active until confirmed**. When applied, AWS
sends each address a confirmation email; the recipient must click the link
before any alerts are delivered to them. Until then the subscription shows as
`PendingConfirmation`.

This is an AWS SNS constraint — there is no API to auto-confirm an email
subscription, and this module deliberately does not try to work around it.
If an address stops receiving alerts, check that its subscription was
confirmed before assuming the module is broken.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topic_arns` | `map(string)` | — (required) | Map of severity tier → SNS topic ARN, from `modules/core`'s `topic_arns` output. |
| `severity_tiers` | `list(string)` | — (required) | Which keys of `topic_arns` to subscribe to. Must be a subset of `topic_arns`' keys. |
| `email_addresses` | `list(string)` | — (required) | Addresses subscribed to every subscribed tier's topic. |

## Output

| Name | Description |
|------|-------------|
| `subscription_arns` | Map of `"<tier>::<email>"` → subscription ARN. ARNs read `PendingConfirmation` until the recipient confirms. |
