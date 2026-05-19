---
name: using-wens-superpowers
description: "Orchestrates the superpowers brainstorm → plan → implement flow with dispatch-agent-driven external review at each stage. Use when starting a feature that warrants the full spec/plan/implement cycle and you want to offload review (and optionally implementation) to a third-party agent CLI."
---

# using-wens-superpowers

A thin orchestrator: set the `WENS_ORCHESTRATED` marker, capture the `WENS_MODE` choice, then invoke `brainstorming`. The forked `brainstorming`, `writing-plans`, and `subagent-driven-development` skills detect the marker and branch into dispatch-agent-driven review loops at their natural injection points. Auto-chain between the three skills is preserved.

This skill does **not** duplicate the content of those skills. It is glue.

## When to use

Type `/using-wens-superpowers` at the start of a development task that warrants the full spec/plan/implement cycle and where you want spec/plan/code review (and optionally implementation) routed to a third-party agent via `dispatch-agent`.

Do **not** use this skill for one-off fixes, quick refactors, or anything that does not need a spec. Use the standard `/brainstorming` (or no skill) for those.

## Prerequisites

- `dispatch-agent` CLI on `PATH`. The wrapper script will exit 127 with an install hint if missing.
- For mode (b): your `dispatch-agent` config must enable bypass flags so the third-party agent can write files.

## Entry checklist

The skill MUST perform these steps in order before invoking `brainstorming`:

1. **Ensure `.gitignore` ignores `docs/tmp/`.** Read the repo-root `.gitignore`. If `docs/tmp/` (or `docs/tmp`) is not present:
   - Check the file ends with `\n`. If not, append one.
   - Append `docs/tmp/\n`.
   - Inform the user once: "Added `docs/tmp/` to `.gitignore` (dispatch-agent artifact directory)."

2. **Confirm `dispatch-agent` is installed.** Run `command -v dispatch-agent`. If absent, tell the user where to install it and STOP — do not proceed.

3. **Ask for mode** via `AskUserQuestion`:
   - (a) **Reviewers dispatched, implementer is a Task-tool subagent.** Recommended — no bypass flags required.
   - (b) **All dispatched** (implementer + both reviewers). Requires `dispatch-agent` config with `--dangerously-skip-permissions` or equivalent. Faster context savings but the operator must trust the third-party agent.

4. **Declare the markers in agent context** by stating, in your own message to the user (and to yourself for future steps): "Running in orchestrated mode: `WENS_ORCHESTRATED=1`, `WENS_MODE=<a|b>`." This is the authoritative marker. Bash tool calls do **not** share shells in Claude Code, so an `export WENS_ORCHESTRATED=1` would not persist; the downstream skills' gate text says "running inside a `using-wens-superpowers` session" and resolves the gate from agent context, not from a shell lookup. For per-call env vars that genuinely need to reach the wrapped binary (e.g., `WENS_DISPATCH_TIMEOUT`), prefix the individual Bash invocation: `WENS_DISPATCH_TIMEOUT=1200 sh skills/using-wens-superpowers/scripts/dispatch.sh implement-task3`.

5. **Invoke brainstorming** via the Skill tool: `Skill(brainstorming)`. The auto-chain from brainstorming → writing-plans → subagent-driven-development carries through the agent's session context — each downstream skill, on entry, sees that it is running inside an orchestrated session and executes its orchestrated branch.

## What happens downstream

| Stage | Skill | Orchestrated behavior |
|---|---|---|
| Spec | `brainstorming` | After spec self-review, loops `dispatch-agent spec-review` until `status: PASS` (10-round user gate). |
| Plan | `writing-plans` | After self-review, loops `dispatch-agent plan-verify` until PASS. Auto-selects subagent-driven-development for execution. |
| Implement | `subagent-driven-development` | Per task: mode (b) dispatches implementer; both modes dispatch spec-compliance + code-review reviewers via `dispatch-agent`. In-skill reviewer prompts are bypassed. |

See the "Orchestrated Mode" sections inside each downstream skill for the exact loop bodies.

## Artifacts

Every `dispatch.sh` call writes:

- `docs/tmp/<UTC-ts>_<pid>-<slug>.md` — rendered prompt
- `docs/tmp/<UTC-ts>_<pid>-<slug>.out.md` — dispatch-agent stdout (the third-party agent's response)

`docs/tmp/` is gitignored. Clean up with `rm -rf docs/tmp` between sessions if desired.

## Prompt templates

- `references/spec-review-prompt.md`
- `references/plan-verify-prompt.md`
- `references/implement-task-prompt.md` (mode b only)
- `references/spec-compliance-review-prompt.md`
- `references/code-review-prompt.md`

All templates use `{{placeholder}}` substitution rendered inline by the main agent. The output contract (YAML frontmatter with `status`) is documented in each template's footer.

## Finalization

After all tasks pass both reviews (per `subagent-driven-development`), the main agent:

1. Appends a single Unreleased entry to `CHANGELOG.md` for the feature.
2. Updates `README.md` / other top-level docs as warranted.
3. Reports completion to the user. Does **not** auto-commit final docs — user runs `/git-release` separately.

## Non-goals

- Not a general dispatch wrapper. Encodes one specific workflow.
- Not concerned with which third-party agent `dispatch-agent` routes to (Codex / Gemini / Claude CLI / etc.) — that is the user's `dispatch-agent` config.
- Does not modify `using-superpowers`; the two coexist. `/using-superpowers` remains the standard entry point for routine work.
