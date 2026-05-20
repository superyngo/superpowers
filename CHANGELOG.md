# Changelog

This file tracks changes to this fork of `obra/superpowers`. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Upstream releases are noted only when this fork diverges from them in a feature-relevant way.

## Unreleased

- Added `using-wens-superpowers` skill: orchestrates brainstorm → plan → implement flow with `dispatch-agent`-driven external review at each stage, gated by `WENS_ORCHESTRATED=1`.
- Modified `brainstorming`, `writing-plans`, `subagent-driven-development` to add `WENS_ORCHESTRATED`-gated dispatch loops. Standalone (unset) behavior unchanged.
- **2026-05-20** — `using-wens-superpowers`: hard-switch wrapper from `dispatch-agent` to `agd`; add 4-tier timeout defaults (spec-review 15 min / plan-verify 20 min / implement 30 min / reviewer 15 min) with empty-output retry; embed scope-guard, severity vocab, and round-discipline blocks into reviewer templates; add TaskCreate mandate, mode (b) bypass probe + cost-gate ordering, tolerant YAML parsing, and `git add -am` safety to `subagent-driven-development`; document `/tmp/` vs `docs/tmp/` policy. Spec: `docs/superpowers/specs/2026-05-20-wens-orchestrator-optimization-design.md`. Plan: `docs/superpowers/plans/2026-05-20-wens-orchestrator-optimization.md`.

## v5.1.0

Upstream release — see `obra/superpowers` history.
