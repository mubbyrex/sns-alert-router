# Tasks — Phase 1: Core Alert Routing

Execute in order. Each task cites the requirement ID(s) it implements (see
`requirements.md`) and the design section it follows (see `design.md`). Do
not mark a task `[x]` until its own verification step passes. Do not start
a task whose dependencies aren't checked off.

If a task seems to require something not described in requirements.md or
design.md, stop and ask — don't invent scope silently (see CLAUDE.md and
the requirements.md "Definition of Done" final check).

---

## Task 0 — Repo scaffolding

**Implements:** none directly (infrastructure for all subsequent tasks)

- [ ] Create directory structure:
  ```
  sns-alert-router/
  ├── CLAUDE.md                       (already exists)
  ├── README.md                       (placeholder for now — written
                                        properly in Task 8)
  ├── LICENSE                         (MIT, or confirm preferred license
                                        with human before adding)
  ├── .gitignore
  ├── specs/core-alert-routing/       (already exists — requirements.md,
                                        design.md, this file)
  ├── modules/
  │   ├── core/
  │   └── receivers/
  │       ├── slack/
  │       └── email/
  └── examples/standalone/
  ```
- [ ] Confirm `modules/receivers/teams/` is NOT created. Its absence is a
      requirement (REQ-6), not an omission to fix.
- [ ] `.gitignore` excludes at minimum: `*.tfstate`, `*.tfstate.*`,
      `.terraform/`, `*.tfvars` (except `*.tfvars.example`).
      `.terraform.lock.hcl` is fine to commit (lockfile, not a secret — but
      confirm this is still best practice at implementation time,
      conventions shift).
- [ ] `terraform init` succeeds in `modules/core/`, `modules/receivers/slack/`,
      and `modules/receivers/email/` independently, each with just a
      provider block, before any real resources are added to any of them.

**Verify:** directory structure matches above (including confirmed absence
of `modules/receivers/teams/`); `terraform init` exits 0 in all three module
directories.

---

## Task 1 — Severity-tiered SNS topics

**Implements:** `REQ-1`
**Design reference:** "Severity taxonomy" section

- [ ] Add `severity_tiers` variable to `modules/core/variables.tf` exactly
      as specified in design.md (map of object, default
      critical/warning/info).
- [ ] Create `aws_sns_topic` resources via `for_each` over `severity_tiers`
      in `modules/core/main.tf`. Topic name should incorporate the tier key
      and be configurable via a name-prefix variable (don't hardcode a
      literal topic name — multiple instances of this module in one account
      must not collide).
- [ ] Add `topic_arns` output (map of tier key → topic ARN) to
      `modules/core/outputs.tf`, per design.md's module interface section.
      This is the only thing `modules/core` exposes to receiver modules.

**Verify:** `terraform validate` passes in `modules/core/`. `terraform plan`
(no apply) with defaults shows exactly 3 `aws_sns_topic` resources
(critical/warning/info). Manually add a 4th tier in a test `.tfvars` and
confirm plan shows 4 without any module code changes — concrete proof
REQ-1's "variable, not hardcoded" requirement actually holds.

---

## Task 2 — Per-topic least-privilege IAM (topic policies)

**Implements:** `REQ-2`
**Design reference:** "IAM boundary" section
**Depends on:** Task 1

- [ ] Add `aws_sns_topic_policy` resources, one per topic (via the same
      `for_each`), scoping `SNS:Publish` to `events.amazonaws.com` only, as
      shown in design.md.
- [ ] Confirm no topic policy uses `Principal: "*"` or any wildcard broader
      than a specific named AWS service principal.

**Verify:** `terraform validate` passes. Read back the rendered policy JSON
(via `terraform plan` output or `terraform console`) for at least one topic
and confirm the `Principal` block is exactly
`{"Service": "events.amazonaws.com"}` — not broader.

---

## Task 3 — Verify current AWS Chatbot resource naming

**Implements:** none directly — research/verification task that Task 4
depends on. Treat as blocking, not optional.

- [ ] Check current `hashicorp/aws` provider documentation for the
      Chatbot/Amazon Q Developer in chat applications resource(s). Confirm:
  - Exact resource name (is `aws_chatbot_slack_channel_configuration`
    still current?)
  - Exact required/optional arguments
  - Exact IAM service principal Chatbot's role must trust (confirm whether
    `chatbot.amazonaws.com` is still correct post-rebrand)
- [ ] Record findings as a short comment block at the top of
      `modules/receivers/slack/main.tf` (the file Task 4 will create)
      citing the provider version checked against, so this doesn't need
      re-verifying every session.

**Verify:** findings are written down before Task 4 starts. If the resource
has been renamed or restructured significantly, stop and flag to the human
before proceeding — this could affect design.md's interface and shouldn't
be silently worked around.

---

## Task 4 — `modules/receivers/slack`

**Implements:** `REQ-3`, `REQ-6` (as the first concrete receiver module
proving the abstraction)
**Design reference:** "`modules/receivers/slack`" section
**Depends on:** Task 1 (topic ARNs exist to subscribe to), Task 3
(confirmed resource naming)

- [ ] Create `modules/receivers/slack/variables.tf` with exactly the
      variables specified in design.md: `topic_arns` (map(string)),
      `severity_tiers` (list(string)), `slack_team_id`, `slack_channel_id`,
      `logging_level` (default `"ERROR"`), `guardrail_policy_arns`
      (list(string), default a small read-only set — finalize exact
      default ARNs now, verified current, not guessed).
- [ ] Add a `validation` block (or `precondition`, whichever is more
      idiomatic at implementation time) on `severity_tiers` that fails
      clearly if any listed tier name is not a key in `topic_arns`. Do not
      let this fail silently or produce a Chatbot config subscribed to
      zero topics.
- [ ] Create the Chatbot configuration resource in
      `modules/receivers/slack/main.tf`, subscribed only to the topic ARNs
      corresponding to `severity_tiers` (filter `topic_arns` down, don't
      subscribe to all of them regardless of input).
- [ ] Create the dedicated IAM role for this receiver: trust policy permits
      only the Chatbot service principal confirmed in Task 3; attach
      `guardrail_policy_arns`.
- [ ] Add `chatbot_configuration_arn` output.

**Verify:** `terraform validate` passes in `modules/receivers/slack/`
standalone (using mock/example `topic_arns` values in a test `.tfvars`,
since this module doesn't create its own topics). Confirm via plan that the
subscribed topics are exactly the filtered subset matching
`severity_tiers` — not all of `topic_arns` regardless of input. Test the
failure case: a `severity_tiers` value not present in `topic_arns` keys
(e.g. `"sev1"`) should fail `terraform plan` with a clear validation error,
not silently succeed or subscribe to nothing.

Also verify, via plan output, that the IAM role's attached policies contain
no `Action` matching `Put`, `Delete`, `Create`, `Update`, or `Write` — i.e.
the guardrail default is genuinely read-only.

---

## Task 5 — `modules/receivers/email`

**Implements:** `REQ-6` (the second receiver module — proves the
abstraction holds for a non-chat delivery mechanism)
**Design reference:** "`modules/receivers/email`" section
**Depends on:** Task 1 (topic ARNs to subscribe to)

- [ ] Create `modules/receivers/email/variables.tf` with `topic_arns`
      (map(string)), `severity_tiers` (list(string)), `email_addresses`
      (list(string)).
- [ ] Create `aws_sns_topic_subscription` resources (protocol `"email"`)
      for every combination of subscribed tier × email address, in
      `modules/receivers/email/main.tf`. Use whichever `for_each`/`for`
      construction is most idiomatic — design.md's sketch is illustrative,
      not prescriptive.
- [ ] Add the same kind of `severity_tiers`-vs-`topic_arns` validation as
      Task 4 (don't duplicate logic by copy-paste without checking it still
      makes sense in this module's shape — but the same protection against
      a typo'd tier name applies here too).
- [ ] Document in this module's own short README/comment that SNS email
      subscriptions require manual confirmation via a link sent to each
      address — this is an AWS constraint, not a bug in the module, and
      should be stated plainly so it isn't mistaken for broken automation.

**Verify:** `terraform validate` passes standalone (mock `topic_arns`).
Confirm via plan that subscription count equals
`len(severity_tiers) × len(email_addresses)` for a test case with 2 tiers
and 2 addresses (expect 4 subscriptions). Same tier-name failure-case test
as Task 4.

---

## Task 6 — EventBridge example pattern with noise filtering

**Implements:** `REQ-4`
**Design reference:** "EventBridge example pattern with noise filtering"
section
**Depends on:** Task 1 (a topic to target)

- [ ] In `examples/standalone/`, add an EventBridge rule matching a
      generic/synthetic event pattern (not tied to a real AWS service —
      this is a documented technique, not a production integration; see
      design.md's note that the original production exclusion list isn't
      being reconstructed or claimed as recovered).
- [ ] Demonstrate an `anything-but` exclusion as the noise-filtering
      technique.
- [ ] Add an `input_transformer` reshaping the matched event into the
      minimum shape from requirements.md: `severity`, `source`, `title`,
      `description`, `timestamp`.
- [ ] Target the transformed event at one of the topics from `modules.core`
      (via its `topic_arns` output, referenced from the standalone
      example's root module).

**Verify:** `terraform validate` passes on the example. Manually trigger
the synthetic pattern (or use `aws events test-event-pattern` or
equivalent) and confirm the transformed payload shape matches the required
fields exactly.

---

## Task 7 — Standalone example, fully wired (core + both receivers)

**Implements:** `REQ-5`, and demonstrates `REQ-6` concretely
**Design reference:** "Standalone consumability" section
**Depends on:** Tasks 1-6 all complete

- [ ] `examples/standalone/main.tf` wires:
  - One `module "core"` instance (default `severity_tiers`).
  - One `module "platform_slack"` (or similarly named) instance of
    `modules/receivers/slack`, with `severity_tiers = ["critical"]` only.
  - One `module "oncall_email"` (or similarly named) instance of
    `modules/receivers/email`, with
    `severity_tiers = ["critical", "warning", "info"]`.
  - The EventBridge example pattern from Task 6, targeting `module.core`'s
    topic ARNs.
- [ ] `examples/standalone/terraform.tfvars.example` provided with clearly
      fake placeholder values (e.g. `T00000000000`, `C00000000000`,
      `oncall@example.com` — not real IDs/addresses) and comments
      explaining where a real consumer finds their actual Slack
      team/channel IDs.
- [ ] `examples/standalone/README.md`: brief — what this example proves
      (standalone usability AND multi-receiver, multi-type, severity-subset
      composition), how to apply it, how to trigger the synthetic event,
      what to expect (Slack message only for critical test events; email
      for any severity).

**Verify:** `terraform validate` and `terraform plan` succeed using only
the `.tfvars.example` values copied to a local (gitignored)
`terraform.tfvars`. Full apply against a real (the human's own, test) AWS
account is the human's call, not something to do automatically — flag
readiness for human-initiated apply rather than applying without being
asked (per CLAUDE.md hard rules).

---

## Task 8 — README (root)

**Implements:** supports the Definition of Done checklist in
requirements.md (the "first 10 lines" requirement) — not a numbered REQ
itself, but required before Phase 1 is done.

- [ ] First section (before any usage instructions) states plainly what
      AWS already provides natively (SNS, EventBridge, Chatbot, the
      CloudWatch→SNS integration) vs. what this project adds (severity
      taxonomy, noise-filtering pattern, IAM boundary, the type-agnostic
      receiver-module abstraction, packaging) — pulling directly from
      CLAUDE.md's framing, not reinventing it.
- [ ] Usage example mirrors `examples/standalone/`, showing the
      core-plus-multiple-receiver-modules composition pattern explicitly —
      this is the clearest way to demonstrate REQ-6 to a reader who hasn't
      seen the design doc.
- [ ] Explicitly states current scope: Slack and email receivers exist and
      are tested; Teams is an honest "the same underlying AWS Chatbot
      pattern supports Teams — not yet built/tested here, see roadmap," not
      a false claim of present support.
- [ ] Roadmap section mentions Phase 2 (ECS reference integration) and
      Phase 3 (Teams receiver module) as planned, not yet built.

**Verify:** a reader who knows AWS but has never seen this repo can state,
after reading only the first 10 lines, what problem this solves that AWS
doesn't already solve out of the box, and can tell from the usage example
alone that adding a new receiver type later doesn't require touching
existing code. (Human judgment call — ask the human to confirm this reads
correctly; don't self-certify.)

---

## Final step — run the Definition of Done checklist

Once Tasks 0-8 are all checked off, go through `requirements.md`'s
"Definition of Done (Phase 1)" checklist literally, item by item, before
telling the human Phase 1 is complete. This is not redundant with the task
verifications above — it's the final cross-check that nothing drifted
across the whole sequence, including the specific checks for "no
`modules/receivers/teams/` directory" and "no Slack/Teams/email references
inside `modules/core/`."
