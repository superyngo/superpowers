---
name: using-wens-superpowers
description: "Orchestrates the superpowers brainstorm → plan → implement flow with agd-driven external review at each stage. Use when starting a feature that warrants the full spec/plan/implement cycle and you want to offload review (and optionally implementation) to a third-party agent CLI."
---

# using-wens-superpowers

A thin orchestrator: set the `WENS_ORCHESTRATED` marker, capture the `WENS_MODE` choice, then invoke `brainstorming`. The forked `brainstorming`, `writing-plans`, and `subagent-driven-development` skills detect the marker and branch into agd-driven review loops at their natural injection points. Auto-chain between the three skills is preserved.

This skill does **not** duplicate the content of those skills. It is glue.

## When to use

Type `/using-wens-superpowers` at the start of a development task that warrants the full spec/plan/implement cycle and where you want spec/plan/code review (and optionally implementation) routed to a third-party agent via `agd`.

Do **not** use this skill for one-off fixes, quick refactors, or anything that does not need a spec. Use the standard `/brainstorming` (or no skill) for those.

## Prerequisites

- `agd` CLI on `PATH` (https://github.com/superyngo/agd). The wrapper script will exit 127 if missing.
- For mode (b): `agd --help` must show a `--dangerously-skip-permissions` (or equivalent bypass) flag so the third-party agent can write files. The entry checklist probes this.

## Entry checklist

The skill MUST perform these steps in order before invoking `brainstorming`:

1. **Ensure `.gitignore` ignores `docs/tmp/`.** Read the repo-root `.gitignore`. If `docs/tmp/` (or `docs/tmp`) is not present:
   - Check the file ends with `\n`. If not, append one.
   - Append `docs/tmp/\n`.
   - Inform the user once: "Added `docs/tmp/` to `.gitignore` (agd artifact directory)."

2. **Confirm `agd` is installed.** Run `command -v agd`. If absent, tell the user to install from https://github.com/superyngo/agd and STOP — do not proceed.

3. **Bypass-flag probe (one-shot).** Run:

   ```sh
   agd --help 2>&1 | grep -qE -- '--dangerously-skip-permissions|--bypass' \
     && echo bypass-ok || echo bypass-missing
   ```

   Cache the result; do not re-probe per dispatch.

4. **Ask for mode** via `AskUserQuestion`:
   - (a) **Reviewers dispatched, implementer is a Task-tool subagent.** Recommended — no bypass flags required.
   - (b) **All dispatched** (implementer + both reviewers). Requires `agd` configured with `--dangerously-skip-permissions` or equivalent. Faster context savings but the operator must trust the third-party agent.

5. **Mode (b) precondition gate.** If the probe (step 3) returned `bypass-missing` AND the user selected mode (b), use `AskUserQuestion`: continue at own risk / abort / switch to mode (a).

6. **Cost estimate preview (informational only — no gate).** Print once:

   > 「Mode (b) 將透過 agd 跑 implementer + 2 reviewers。實際 dispatch 數 = 3 × (plan task 數)，將於 subagent-driven-development 開跑前再次確認。」

   The actual cost gate is enforced in `subagent-driven-development` once the plan exists.

7. **Declare the markers in agent context** by stating, in your own message to the user (and to yourself for future steps): "Running in orchestrated mode: `WENS_ORCHESTRATED=1`, `WENS_MODE=<a|b>`." This is the authoritative marker. Bash tool calls do **not** share shells in Claude Code, so an `export WENS_ORCHESTRATED=1` would not persist; the downstream skills' gate text says "running inside a `using-wens-superpowers` session" and resolves the gate from agent context, not from a shell lookup. For per-call env vars that genuinely need to reach the wrapped binary (e.g., `WENS_DISPATCH_TIMEOUT`), prefix the individual Bash invocation: `WENS_DISPATCH_TIMEOUT=1200 sh skills/using-wens-superpowers/scripts/dispatch.sh implement-task3`.

8. **Invoke brainstorming** via the Skill tool: `Skill(brainstorming)`. The auto-chain from brainstorming → writing-plans → subagent-driven-development carries through the agent's session context — each downstream skill, on entry, sees that it is running inside an orchestrated session and executes its orchestrated branch.

## What happens downstream

| Stage | Skill | Orchestrated behavior |
|---|---|---|
| Spec | `brainstorming` | After spec self-review, loops `agd` spec-review (tier 15 min, R2+ verify-only with R1 issues inline) until `status: PASS` (10-round user gate). |
| Plan | `writing-plans` | After self-review, loops `agd` plan-verify (tier 20 min) until PASS. Auto-selects subagent-driven-development for execution. |
| Implement | `subagent-driven-development` | Per task: mode (b) dispatches implementer (tier 30 min); both modes dispatch spec-compliance + code-review reviewers (tier 15 min). Cost estimate gate before first dispatch in mode (b). TaskCreate is mandatory for progress tracking. |

See the "Orchestrated Mode" sections inside each downstream skill for the exact loop bodies.

## Artifacts

Every `dispatch.sh` call writes:

- `docs/tmp/<UTC-ts>_<pid>-<slug>.md` — rendered prompt
- `docs/tmp/<UTC-ts>_<pid>-<slug>.out.md` — agd stdout+stderr (the third-party agent's response; stderr merged via `2>>` per §10.2 risk acceptance)

`docs/tmp/` is gitignored. Clean up with `rm -rf docs/tmp` between sessions if desired.

## `/tmp/` vs `docs/tmp/` — When to use which

`docs/tmp/` — repo-local, gitignored, persists across the session:
- All `dispatch.sh` artifacts (`*.md` prompt, `*.out.md` agd response).
- Anything that may need to be audited or quoted in fix iterations.
- Anything a future reviewer round may need to reread.

`/tmp/` — system tmp, ephemeral, cross-repo:
- Main agent ad-hoc scratch (e.g. `/tmp/task5-body.md` for extracting a task body from the plan before dispatch).
- One-shot intermediate files with no audit value.
- Pipes between commands.

Rule of thumb: if `dispatch.sh` wrote it, it goes in `docs/tmp/`. If the main agent wrote it directly via Bash, it goes in `/tmp/`. Clean either at session end if desired (`rm -rf docs/tmp` for the repo side).

## Prompt templates

- `references/spec-review-prompt.md`
- `references/plan-verify-prompt.md`
- `references/implement-task-prompt.md` (mode b only)
- `references/spec-compliance-review-prompt.md`
- `references/code-review-prompt.md`

All templates use `{{placeholder}}` substitution rendered inline by the main agent. The output contract (YAML frontmatter with `status`) is documented in each template's footer. Placeholders now include `{{stage}}`, `{{plan_task_headers}}`, `{{round}}`, `{{prev_round}}`, and `{{r1_issues_inline}}` in addition to the existing per-template ones. See `skills/subagent-driven-development/SKILL.md` for the rendering contract.

## Finalization

After all tasks pass both reviews (per `subagent-driven-development`), the main agent:

1. Appends a single Unreleased entry to `CHANGELOG.md` for the feature.
2. Updates `README.md` / other top-level docs as warranted.
3. Reports completion to the user. Does **not** auto-commit final docs — user runs `/git-release` separately.
4. When the main agent does need to commit (e.g. changelog updates), use `git add <specific-files>` only. Never `git commit -am` or `git add -A` in orchestrated mode — see `subagent-driven-development` for rationale.

## Non-goals

- Not a general dispatch wrapper. Encodes one specific workflow.
- Not concerned with which third-party agent `agd` routes to (Codex / Gemini / Claude CLI / etc.) — that is the user's `agd` config.
- Does not modify `using-superpowers`; the two coexist. `/using-superpowers` remains the standard entry point for routine work.
