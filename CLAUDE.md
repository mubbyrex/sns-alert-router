# CLAUDE.md — sns-alert-router

## What this project is

A Terraform module that provides a severity-tiered, noise-filtered alert
routing backbone on AWS, delivered to Slack or Microsoft Teams via AWS
Chatbot. The goal is to be **generic infrastructure** — not a Slack/Teams
notifier, not an ECS-specific tool. Any AWS service that can publish to SNS
or emit an EventBridge event is a valid source. ECS is the first reference
integration (proves the pattern), not the point of the module.

## What AWS already provides vs. what this project adds

Read this before writing any code — it defines the boundary of what we
should and should not build.

AWS already gives us, natively, with zero glue required:
- SNS (pub/sub topics)
- EventBridge (event pattern matching + routing + `input_transformer`)
- CloudWatch Alarms → SNS (automatic, no extra config)
- AWS Chatbot (SNS topic → Slack/Teams channel delivery)

AWS does NOT give us, and this project supplies:
- A severity taxonomy (which topics exist, what "critical" means)
- Noise-filtering EventBridge patterns (e.g. excluding deploy-triggered ECS
  task stops from "unexpected stop" alerts)
- `input_transformer` templates that turn raw AWS event JSON into a
  readable, actionable payload (title, severity, links)
- Least-privilege IAM roles/policies for Chatbot, scoped per use case
- Packaging of all of the above as a reusable, parameterized module

**If a proposed change just re-implements something AWS Chatbot, SNS, or
EventBridge already does — stop. That's over-engineering. The value here is
judgment encoded as Terraform, not new application code sitting on top of
AWS's existing plumbing.**

## Hard rules

- No hardcoded AWS account IDs, Slack team/channel IDs, Teams tenant/team
  IDs, or any other real identifier — anywhere, ever, including in comments
  or examples. Use variables with no default, or clearly fake placeholder
  values (e.g. `123456789012`, `T00000000`) in examples.
- Never commit `.tfstate`, `.tfstate.backup`, or `.tfvars` with real values.
  `.gitignore` must exclude these from day one.
- Run `terraform fmt -check` and `terraform validate` before considering any
  task complete. Do not mark a task done in tasks.md until both pass.
- Do not run `terraform apply` against real AWS infrastructure without
  explicit human go-ahead in the session. Plan is fine; apply is not, unless
  asked.
- Prefer AWS-managed IAM policies only where genuinely appropriate; default
  to least-privilege custom policies for anything touching write actions.
- Every resource that supports tagging gets tagged (`Project`, `Environment`,
  `ManagedBy = "terraform"` at minimum).

## Where the active spec lives

Specs are organized by phase, one folder per phase, under `specs/`. Each
phase has `requirements.md`, `design.md`, and `tasks.md`. Read
`requirements.md` and `design.md` in full before starting work on
`tasks.md` — they contain the reasoning and constraints that the task list
assumes you already know.

**Do this at the start of every session that touches this repo, not just
the first one.** Do not rely on memory of a previous session or an earlier
point in a long conversation. Re-read the active phase's `requirements.md`
and `design.md` fresh each time, even if you (or a prior session) already
read them. Long sessions drift; re-reading the spec is the correction
mechanism, not optional context.

When marking a task in `tasks.md` complete, confirm it cites a requirement
ID from the active phase's `requirements.md` (e.g. `REQ-3`). A task with no
requirement ID, or one invented mid-session that doesn't map to anything in
requirements.md, is a signal to stop and ask the human before continuing —
not to proceed and reconcile later.

Current active phase: `specs/core-alert-routing/` (Phase 1 — the generic
backbone: severity-tiered SNS topics, EventBridge pattern examples, Chatbot
Slack delivery, least-privilege IAM. No ECS-specific resources in this
phase — that's Phase 2.)

Future phases (not yet started): `specs/ecs-integration/` (Phase 2),
`specs/teams-support/` (Phase 3).

## Repo conventions

- Terraform module lives in `modules/core/` (Phase 1) with additional
  modules per integration under `modules/integrations/<name>/` as phases
  land.
- Reference/example usage lives in `examples/<name>/` — runnable, but
  never applied automatically.
- Variable naming: `snake_case`, descriptive, no abbreviations unless
  extremely standard (`arn`, `id`, `sns`, `iam`).
- All variables that are inherently sensitive or environment-specific
  (account IDs, channel IDs, ARNs supplied by the consumer) have no
  default and a clear description.

## Status

Repo scaffolding in progress. See `specs/core-alert-routing/tasks.md` for
current implementation checklist once it exists.
