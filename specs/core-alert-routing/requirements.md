# Requirements — Phase 1: Core Alert Routing

## Purpose

Establish the generic, source-agnostic alerting backbone: severity-tiered
SNS topics, example EventBridge routing patterns (including noise
filtering), AWS Chatbot delivery to Slack, and least-privilege IAM. This
phase contains no ECS-specific or other service-specific resources — those
are reference integrations layered on top in later phases. Phase 1 must be
useful and demonstrable entirely on its own, using a synthetic/example event
source if needed to prove the pattern.

## Functional requirements

Each requirement has a stable ID (`REQ-1`, `REQ-2`, ...). `tasks.md` must
cite which requirement ID(s) each task implements. If a task doesn't map to
any requirement ID below, stop and ask whether the requirement list is
incomplete or the task is scope creep — don't silently proceed either way.

1. **`REQ-1` — Severity-tiered topics.** The module creates a configurable set of SNS
   topics representing severity tiers. Default tiers: `critical`,
   `warning`, `info`. The set of tiers must be a variable (list of strings
   or map), not hardcoded — a consumer should be able to add a `security`
   tier without modifying the module's source.

2. **`REQ-2` — Per-topic least-privilege IAM.** Each topic has a topic policy scoped
   to only the AWS service principals that need to publish to it (e.g.
   `events.amazonaws.com` for EventBridge-sourced alerts). No topic accepts
   publishes from `"*"` or an overly broad principal.

3. **`REQ-3` — AWS Chatbot Slack receiver module.** A separate module,
   `modules/receivers/slack/`, provisions one
   `aws_chatbot_slack_channel_configuration` resource (or current
   equivalent — verify against latest provider docs; AWS renamed Chatbot to
   "Amazon Q Developer in chat applications" and resource/console naming
   may have shifted). This module takes `topic_arns` (map, from core's
   output) and `severity_tiers` (list, which of those tiers this specific
   receiver instance subscribes to) as inputs, plus Slack-specific
   configuration (`slack_team_id`, `slack_channel_id`). It provisions:
   - Its own dedicated IAM role, assumed only by the current Chatbot
     service principal (verify exact name, do not assume
     `chatbot.amazonaws.com` without checking).
   - Guardrail policies that are read-only (no write/mutate AWS actions
     available from chat).
   - `logging_level` configurable, default `ERROR`.
   A consumer wanting multiple Slack channels (e.g. a critical-only on-call
   channel and a separate everything channel) declares multiple instances
   of this module — the module itself handles exactly one receiver. See
   REQ-6 for why this is a separate module rather than a multi-receiver
   variable inside one module.

4. **`REQ-4` — Example EventBridge pattern with noise filtering.** At least one
   worked example of an EventBridge rule that:
   - Matches a specific AWS event type.
   - Demonstrates a noise-filtering technique (e.g. `anything-but`) that
     excludes a known-routine variant of that event from triggering a
     higher-severity topic.
   - Uses `input_transformer` to reshape the raw event into a clean payload
     with at minimum: `severity`, `source`, `title`, `description`,
     `timestamp`.
   This can use a generic/synthetic event pattern if no specific service
   integration is in scope yet — the point is demonstrating the *pattern*,
   reusable by any future integration.

5. **`REQ-5` — Module is consumable standalone.** A user with no ECS, no
   CodePipeline, nothing — just a desire to route severity-tiered alerts to
   one or more receivers — can use `modules/core` plus one or more receiver
   modules and get value. Verify this by writing an `examples/standalone/`
   that wires `modules/core` with a trivial synthetic event source (e.g. a
   manually-published test message to the critical topic) and at least two
   receiver module instances (e.g. one Slack receiver subscribed to
   critical only, one email receiver subscribed to everything) —
   demonstrating both the severity-subset routing and the multi-receiver,
   multi-type composition from REQ-6, not just a single channel getting
   everything.

6. **`REQ-6` — Receiver delivery is type-agnostic and independently
   extensible.** `modules/core` has zero knowledge of delivery mechanisms —
   it only creates severity-tiered SNS topics (REQ-1) and exposes their
   ARNs as an output (`topic_arns`). Each delivery mechanism is its own
   small module under `modules/receivers/<type>/`, sharing an identical
   input contract: `topic_arns` (map) + `severity_tiers` (list, which tiers
   *this* receiver instance subscribes to) + type-specific configuration.
   A consumer composes as many receiver module instances as they want, in
   any combination of types, by declaring multiple `module` blocks in their
   own Terraform — there is no single `receivers = {...}` variable with a
   `type` discriminator inside one monolithic module, and `modules/core`
   never changes when a new receiver type is added. Phase 1 ships
   `modules/receivers/slack/` (REQ-3, tested) and `modules/receivers/email/`
   (trivial — `aws_sns_topic_subscription` with `protocol = "email"` per
   subscribed tier — proves the abstraction holds for a genuinely different
   delivery mechanism, not just "another chat app"). `modules/receivers/
   teams/` is reserved for Phase 3 and must not be stubbed out or partially
   built in Phase 1 — its absence now is intentional, not an oversight.

## Non-functional requirements

- No hardcoded account IDs, Slack team IDs, or channel IDs anywhere in
  module source or examples. (See CLAUDE.md hard rules.)
- `terraform validate` and `terraform fmt -check` pass with zero warnings.
- README for this module explains, in the first few lines, what AWS already
  provides natively vs. what this module adds — this is a credibility
  signal, not just documentation (see CLAUDE.md "what AWS already provides"
  section — this framing should appear in the README too).
- Variables that are inherently consumer-specific (Slack team ID, channel
  ID, account ID) have no default value and a clear, accurate description
  pointing to where the consumer finds that value in their own AWS/Slack
  setup.

## Explicitly out of scope for Phase 1

- ECS-specific resources, alarms, or event patterns (Phase 2).
- Microsoft Teams channel configuration — `modules/receivers/teams/` does
  not exist yet (Phase 3). REQ-6 establishes the abstraction it will slot
  into; it does not build it early.
- Any custom Lambda function for message formatting or routing logic — if
  we find ourselves wanting one, stop and reconsider; EventBridge
  `input_transformer` should cover formatting needs natively. A Lambda here
  would likely indicate we're rebuilding something AWS already does.
- A config language, custom DSL, or abstraction layer beyond Terraform
  variables and module composition — keep the interface to "declare a core
  module and one or more receiver modules," not "learn our routing
  language."
- A single monolithic "receivers" variable with a type discriminator
  inside one module. This was considered and rejected — see REQ-6 and
  design.md for why per-type modules were chosen instead.

## Open questions to resolve during design

- Exact current resource name(s) for AWS Chatbot in the Terraform AWS
  provider — confirm whether `aws_chatbot_slack_channel_configuration` is
  still current or has been renamed/deprecated given AWS's Chatbot → Amazon
  Q Developer in chat applications rebrand.
- Whether topic-per-severity or a single topic with message-attribute-based
  filtering is the better default — lean topic-per-severity (simpler
  subscriber model, matches the source material), but worth a sentence in
  design.md on why.

## Definition of Done (Phase 1)

This checklist is the anti-drift anchor. Run through it literally,
independent of how implementation went, before considering Phase 1 done.
If anything here fails, Phase 1 is not done — go back to tasks.md, not
forward to Phase 2.

- [ ] Every requirement above (`REQ-1` through `REQ-6`) has at least one
      task in `tasks.md` that cites it, and that task is complete.
- [ ] `terraform validate` and `terraform fmt -check` pass with zero errors
      and zero warnings on `modules/core/`, `modules/receivers/slack/`, and
      `modules/receivers/email/`.
- [ ] `modules/core` contains zero references to Slack, Teams, email, or
      any other delivery-specific resource type or variable name. `grep`
      for "slack", "teams", "email" (case-insensitive) inside
      `modules/core/` returns nothing.
- [ ] `modules/receivers/teams/` does not exist as a directory. Its absence
      is verified, not assumed.
- [ ] `grep` across the entire repo for anything that looks like a real AWS
      account ID (12 consecutive digits), a Slack team ID pattern (`T` +
      alphanumeric), or any string that isn't an obvious placeholder —
      zero hits outside of comments explicitly marked as examples with
      fake values.
- [ ] `examples/standalone/` applies cleanly using only a synthetic test
      event (no ECS, no CodePipeline, nothing service-specific) and a
      message published to the critical topic visibly reaches Slack.
- [ ] No Lambda function exists anywhere in `modules/core/` for message
      formatting or routing. (If one exists, stop — re-read the "explicitly
      out of scope" section above and resolve why before proceeding.)
- [ ] README's first 10 lines state, explicitly, what AWS already provides
      natively vs. what this module adds. A reader who knows AWS but not
      this repo should understand the value-add without reading further.
- [ ] Re-read this entire requirements.md top to bottom one final time and
      confirm nothing was built that isn't traceable to a requirement ID.
      Anything extra gets removed or moved into a new, explicitly-named
      requirement — it doesn't stay in as an unplanned addition.

