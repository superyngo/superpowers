# wens-superpowers Orchestrator — Round-2 Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the spec at `docs/superpowers/specs/2026-05-20-wens-orchestrator-optimization-design.md` — hard-switch the dispatch wrapper from `dispatch-agent` to `agd`, add 4-tier timeout defaults with empty-output retry, embed scope-guard / severity-vocab / round-discipline blocks into five reviewer prompt templates, and update three downstream skills' orchestrated branches (TaskCreate mandate, cost-gate ordering, tolerant YAML parsing, plan-task-headers carry, git-safety).

**Architecture:** Single-PR, doc-and-shell only. No new files except by spec (`dispatch.sh` rewrite stays single file). Verification is grep-based gates (§9.1 of spec) + dispatch.sh smoke (§9.2). Tasks are file-boundary scoped — each task touches a disjoint set of files (the orchestrator SKILL.md, the wrapper, the five templates as a unit, then each downstream skill, then acceptance/CHANGELOG).

**Tech Stack:** POSIX `sh`, Markdown, ripgrep (`rg`), git. No language toolchains.

---

## Spec mapping (for reviewer scope reference)

| Spec § | Implementing Task |
|---|---|
| §3 file structure | Tasks 1-7 collectively |
| §4 dispatch.sh | Task 2 |
| §5 reviewer templates | Task 3 |
| §6 subagent-driven-development | Task 4 |
| §7 brainstorming + writing-plans | Tasks 5 & 6 |
| §8 using-wens-superpowers SKILL.md | Task 1 |
| §9 acceptance gates | Task 7 |
| §10 out-of-scope/risks | (no code) |
| §11 evaluation chapter | (no code) |

---

## Task 1: Update `using-wens-superpowers/SKILL.md` for agd + bypass probe + /tmp policy

**Files:**
- Modify: `skills/using-wens-superpowers/SKILL.md`

Implements spec §8.1–§8.6. No dependency on other tasks.

- [ ] **Step 1: Replace Prerequisites section**

Open `skills/using-wens-superpowers/SKILL.md`. Replace the existing `## Prerequisites` block (currently lines ~18-21) with:

```markdown
## Prerequisites

- `agd` CLI on `PATH` (https://github.com/superyngo/agd). The wrapper script will exit 127 if missing.
- For mode (b): `agd --help` must show a `--dangerously-skip-permissions` (or equivalent bypass) flag so the third-party agent can write files. The entry checklist probes this.
```

- [ ] **Step 2: Replace Entry checklist with 7-step version**

Replace the existing `## Entry checklist` section in full with:

```markdown
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
```

- [ ] **Step 3: Replace "What happens downstream" table rows**

Find the `## What happens downstream` section. Replace the three table rows with:

```markdown
| Stage | Skill | Orchestrated behavior |
|---|---|---|
| Spec | `brainstorming` | After spec self-review, loops `agd` spec-review (tier 15 min, R2+ verify-only with R1 issues inline) until `status: PASS` (10-round user gate). |
| Plan | `writing-plans` | After self-review, loops `agd` plan-verify (tier 20 min) until PASS. Auto-selects subagent-driven-development for execution. |
| Implement | `subagent-driven-development` | Per task: mode (b) dispatches implementer (tier 30 min); both modes dispatch spec-compliance + code-review reviewers (tier 15 min). Cost estimate gate before first dispatch in mode (b). TaskCreate is mandatory for progress tracking. |
```

- [ ] **Step 4: Insert new `/tmp/` vs `docs/tmp/` policy section**

After the `## Artifacts` section and before `## Prompt templates`, add a new section verbatim:

```markdown
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
```

- [ ] **Step 5: Append placeholder note to `## Prompt templates`**

At the very end of the `## Prompt templates` section, append:

```markdown
All templates use `{{placeholder}}` substitution rendered inline by the main agent. Placeholders now include `{{stage}}`, `{{plan_task_headers}}`, `{{round}}`, `{{prev_round}}`, and `{{r1_issues_inline}}` in addition to the existing per-template ones. See `skills/subagent-driven-development/SKILL.md` for the rendering contract.
```

- [ ] **Step 6: Update `## Artifacts` wording**

Change the bullet wording inside `## Artifacts`:

- old: `docs/tmp/<UTC-ts>_<pid>-<slug>.out.md` — dispatch-agent stdout (the third-party agent's response)
- new: `docs/tmp/<UTC-ts>_<pid>-<slug>.out.md` — agd stdout+stderr (the third-party agent's response; stderr merged via `2>>` per §10.2 risk acceptance)

- [ ] **Step 7: Append Finalization step 4 (git-safety)**

In the `## Finalization` numbered list (steps 1-3 currently), append:

```markdown
4. When the main agent does need to commit (e.g. changelog updates), use `git add <specific-files>` only. Never `git commit -am` or `git add -A` in orchestrated mode — see `subagent-driven-development` for rationale.
```

- [ ] **Step 8: Update `description` frontmatter and any remaining `dispatch-agent` mentions**

Change the `description:` line in the YAML frontmatter (line 3) so the substring `dispatch-agent-driven` becomes `agd-driven`, and `third-party agent CLI` stays as-is.

In the `## When to use` paragraph, change `via dispatch-agent` to `via agd`.

In `## Non-goals`, change `via `dispatch-agent`` to `via `agd`` and any other `dispatch-agent` literal to `agd`.

- [ ] **Step 9: Verify**

Run:

```sh
sh -n /dev/null  # sanity
test "$(rg -n 'dispatch-agent' skills/using-wens-superpowers/SKILL.md | wc -l)" -eq 0
rg -q '`agd` CLI on `PATH`' skills/using-wens-superpowers/SKILL.md
rg -q 'bypass-missing|bypass-flag probe' skills/using-wens-superpowers/SKILL.md
rg -q 'system tmp' skills/using-wens-superpowers/SKILL.md
rg -q 'tier 15 min|tier 20 min|tier 30 min' skills/using-wens-superpowers/SKILL.md
rg -q '\{\{prev_round\}\}' skills/using-wens-superpowers/SKILL.md
rg -q 'git add <specific-files>' skills/using-wens-superpowers/SKILL.md
```

All commands must exit 0.

- [ ] **Step 10: Commit**

```sh
git add skills/using-wens-superpowers/SKILL.md
git commit -m "feat(using-wens-superpowers): switch to agd, add bypass probe and /tmp policy"
```

---

## Task 2: Rewrite `dispatch.sh` (agd hard switch + tier table + empty-output retry)

**Files:**
- Modify: `skills/using-wens-superpowers/scripts/dispatch.sh`

Implements spec §4. Independent of Task 1 (Task 1's SKILL.md doesn't import dispatch.sh content; runtime contract is what matters).

- [ ] **Step 1: Replace `dispatch.sh` with the new wrapper**

Overwrite `skills/using-wens-superpowers/scripts/dispatch.sh` with exactly:

```sh
#!/bin/sh
# dispatch.sh — wraps `agd dispatch -f` for using-wens-superpowers.
# Reads prompt from stdin; writes prompt + .out.md to
# docs/tmp/<ts>_<pid>-<slug>.{md,out.md}. Emits prompt=, out=, timeout=,
# tier= on stderr (+ retry= on retry). Exit code mirrors agd (127 if not
# on PATH, 2 if argv malformed). Override per-call via
# WENS_DISPATCH_TIMEOUT (seconds).
set -u

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "dispatch.sh: missing <phase-slug> argument" >&2
  echo "usage: cat prompt.md | dispatch.sh <phase-slug>" >&2
  exit 2
fi

if ! command -v agd >/dev/null 2>&1; then
  echo "dispatch.sh: 'agd' not found on PATH." >&2
  echo "  Install from https://github.com/superyngo/agd" >&2
  echo "  and ensure it is on \$PATH before re-running." >&2
  exit 127
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TMPDIR_ABS="$REPO_ROOT/docs/tmp"
mkdir -p "$TMPDIR_ABS"

SLUG=$(printf '%s' "$SLUG" | sed 's/[^A-Za-z0-9._-]/-/g')
TS=$(date -u +%Y%m%dT%H%M%SZ)
BASE="${TS}_$$-${SLUG}"
PROMPT="$TMPDIR_ABS/${BASE}.md"
OUT="$TMPDIR_ABS/${BASE}.out.md"

cat > "$PROMPT"

case "$SLUG" in
  spec-review*)                          TIER=spec-review;  DEFAULT=900  ;;
  plan-verify*)                          TIER=plan-verify;  DEFAULT=1200 ;;
  implement-task*)                       TIER=implement;    DEFAULT=1800 ;;
  spec-compliance-review*|code-review*)  TIER=review;       DEFAULT=900  ;;
  *)                                     TIER=review;       DEFAULT=900  ;;
esac
TIMEOUT="${WENS_DISPATCH_TIMEOUT:-$DEFAULT}"

echo "prompt=$PROMPT" >&2
echo "out=$OUT" >&2
echo "timeout=$TIMEOUT tier=$TIER" >&2

run_once() {
  agd dispatch -f "$PROMPT" --timeout "$TIMEOUT" > "$OUT" 2>>"$OUT"
}

run_once
RC=$?

# Empty-output / missing-frontmatter retry (one shot).
if [ ! -s "$OUT" ] || ! grep -qE '^(---|status:)' "$OUT"; then
  REASON=empty_output
  [ -s "$OUT" ] && REASON=no_frontmatter
  echo "retry=1 reason=$REASON" >&2
  run_once
  RC=$?
fi

exit $RC
```

- [ ] **Step 2: Syntax check**

```sh
sh -n skills/using-wens-superpowers/scripts/dispatch.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Fake-agd smoke (validates empty-retry, tier table)**

```sh
mkdir -p /tmp/fake-agd-bin
cat > /tmp/fake-agd.sh <<'EOF'
#!/usr/bin/env sh
# Mimics `agd dispatch -f <prompt> --timeout <s>`.
# First call: exit 0 with no output (triggers retry).
# Second call: emit canonical PASS frontmatter.
state_file=/tmp/fake-agd-state
if [ -f "$state_file" ]; then
  printf -- '---\nstatus: PASS\nissues: []\n---\n'
else
  touch "$state_file"
  :  # exit 0 with no output
fi
EOF
chmod +x /tmp/fake-agd.sh
ln -sf /tmp/fake-agd.sh /tmp/fake-agd-bin/agd
rm -f /tmp/fake-agd-state

# Save real PATH; prepend fake-agd
ORIG_PATH="$PATH"
PATH="/tmp/fake-agd-bin:$PATH"

# Test 1: retry triggered + spec-review tier
echo "test prompt" | sh skills/using-wens-superpowers/scripts/dispatch.sh spec-review-r1 2> /tmp/stderr1.log
grep -q 'retry=1 reason=empty_output' /tmp/stderr1.log
grep -q 'timeout=900 tier=spec-review' /tmp/stderr1.log

# Test 2: implement tier
rm -f /tmp/fake-agd-state
echo "test" | sh skills/using-wens-superpowers/scripts/dispatch.sh implement-task5 2> /tmp/stderr2.log
grep -q 'timeout=1800 tier=implement' /tmp/stderr2.log

# Test 3: plan-verify tier
rm -f /tmp/fake-agd-state
echo "test" | sh skills/using-wens-superpowers/scripts/dispatch.sh plan-verify-r1 2> /tmp/stderr3.log
grep -q 'timeout=1200 tier=plan-verify' /tmp/stderr3.log

# Test 4: WENS_DISPATCH_TIMEOUT override
rm -f /tmp/fake-agd-state
echo "test" | WENS_DISPATCH_TIMEOUT=42 sh skills/using-wens-superpowers/scripts/dispatch.sh code-review-task9 2> /tmp/stderr4.log
grep -q 'timeout=42 tier=review' /tmp/stderr4.log

PATH="$ORIG_PATH"
echo "smoke OK"
```

Expected final output: `smoke OK`. Any grep failure stops the script via `set -u`-equivalent (manual: if any grep returns non-zero, fix before commit).

- [ ] **Step 4: Clean up smoke artifacts and any test files dropped in docs/tmp/**

```sh
rm -rf /tmp/fake-agd-bin /tmp/fake-agd.sh /tmp/fake-agd-state /tmp/stderr*.log
# docs/tmp/ artifacts from this smoke can stay (gitignored)
```

- [ ] **Step 5: Commit**

```sh
git add skills/using-wens-superpowers/scripts/dispatch.sh
git commit -m "feat(dispatch): hard-switch to agd; add tier timeouts and empty-output retry"
```

---

## Task 3: Embed common blocks into all 5 reviewer prompt templates

**Files:**
- Modify: `skills/using-wens-superpowers/references/spec-review-prompt.md`
- Modify: `skills/using-wens-superpowers/references/plan-verify-prompt.md`
- Modify: `skills/using-wens-superpowers/references/implement-task-prompt.md`
- Modify: `skills/using-wens-superpowers/references/spec-compliance-review-prompt.md`
- Modify: `skills/using-wens-superpowers/references/code-review-prompt.md`

Implements spec §5. Block matrix (spec §5.5):

| Template                          | Scope Guard | Plan list | Severity | Round Discipline |
|-----------------------------------|:-----------:|:---------:|:--------:|:----------------:|
| spec-review-prompt.md             | ✓           | ✗         | ✓        | ✓                |
| plan-verify-prompt.md             | ✓           | ✓         | ✓        | ✓                |
| implement-task-prompt.md          | ✓           | ✗         | ✗        | ✗                |
| spec-compliance-review-prompt.md  | ✓           | ✓         | ✓        | ✓                |
| code-review-prompt.md             | ✓           | ✓         | ✓        | ✓                |

- [ ] **Step 1: Define the four block strings once (use these verbatim across templates)**

Keep these blocks at the top of your scratch buffer to copy into each template.

**Block A — Scope Guard** (all 5 templates). `{{stage}}` is per-template (`spec` / `plan` / `task N`):

```markdown
## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.
```

**Block B — Plan Task Header List** (plan-verify, spec-compliance-review, code-review only):

```markdown
## Other tasks in plan (for scope reference, NOT for review)

{{plan_task_headers}}

Use this list to recognize findings that belong to a different task than the one being reviewed. Those findings are out of scope.
```

**Block C — Severity Vocabulary** (4 reviewer templates, NOT implement-task):

```markdown
## Severity (CLOSED VOCABULARY)

Each issue MUST use exactly one of:
- `blocker` — would break correctness, security, or the acceptance gates.
- `major`   — substantive design or correctness problem, not blocking.
- `minor`   — style, naming, doc nit.

Do NOT invent other severities (no `medium`, `low`, `pass-note`, `nit`, etc.).
```

**Block D — Round Discipline (two marked variants)** (same 4 templates as Block C):

```markdown
## Round Discipline

<!-- ROUND-1-BLOCK -->
(Round 1 — focused review)

Perform a focused review. Spot-check 3-5 load-bearing claims. Before emitting any finding, grep to verify the file/symbol/line actually exists.
<!-- /ROUND-1-BLOCK -->

<!-- R2-PLUS-BLOCK -->
(Round {{round}} — verify-only mode)

You are in **verify-only mode**. The previous-round issues are listed below under "R{{prev_round}} issues to verify". For each, confirm resolution: `resolved | unresolved | partially-resolved`. You MAY add NEW findings ONLY at severity `blocker`. Do NOT add `major` or `minor` findings — those wait for the next iteration.

### R{{prev_round}} issues to verify
{{r1_issues_inline}}
<!-- /R2-PLUS-BLOCK -->
```

(The main agent strips one of the two marked sub-blocks at render time per spec §5.4; the template carries both.)

- [ ] **Step 2: Update `spec-review-prompt.md`**

Read the current content. Modify so the resulting file is:

```markdown
# Spec Review — Round {{round}}

You are reviewing a design spec for a software feature. The spec lives at:

`{{spec_path}}`

The current stage is `{{stage}}`.

## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.

Read the spec carefully and assess whether it is implementation-ready. Focus on:

1. **Completeness** — are all decisions made, or are there TBDs / open questions left implicit?
2. **Consistency** — do sections contradict each other? Do statements about behavior, file layout, and contracts agree?
3. **Implementability** — could a skilled engineer hand this to a fresh team without further clarification? Are there hidden assumptions about the runtime, tools, or environment?
4. **Scope** — is the scope coherent, or does it bundle independent subsystems that should be split?
5. **Risks** — are tradeoffs surfaced, with mitigations or accepted-risk statements?

## Severity (CLOSED VOCABULARY)

Each issue MUST use exactly one of:
- `blocker` — would break correctness, security, or the acceptance gates.
- `major`   — substantive design or correctness problem, not blocking.
- `minor`   — style, naming, doc nit.

Do NOT invent other severities (no `medium`, `low`, `pass-note`, `nit`, etc.).

## Round Discipline

<!-- ROUND-1-BLOCK -->
(Round 1 — focused review)

Perform a focused review. Spot-check 3-5 load-bearing claims. Before emitting any finding, grep to verify the file/symbol/line actually exists.
<!-- /ROUND-1-BLOCK -->

<!-- R2-PLUS-BLOCK -->
(Round {{round}} — verify-only mode)

You are in **verify-only mode**. The previous-round issues are listed below under "R{{prev_round}} issues to verify". For each, confirm resolution: `resolved | unresolved | partially-resolved`. You MAY add NEW findings ONLY at severity `blocker`. Do NOT add `major` or `minor` findings — those wait for the next iteration.

### R{{prev_round}} issues to verify
{{r1_issues_inline}}
<!-- /R2-PLUS-BLOCK -->

## Output contract

Your response MUST begin with a YAML frontmatter block of the exact shape below. Free-form prose may follow.

```yaml
---
status: PASS | ISSUES_FOUND
issues:
  - severity: blocker | major | minor
    location: "<section name or file:line>"
    description: "<what's wrong>"
    suggestion: "<concrete fix or direction>"
---
```

- Use `status: PASS` only when there are zero blockers and zero majors.
- For `ISSUES_FOUND`, list every issue (do not summarize); the main agent will iterate.
- `issues: []` is required (empty list) when status is PASS.
```

- [ ] **Step 3: Update `plan-verify-prompt.md`**

Replace the file content with:

```markdown
# Plan vs. Spec Consistency Check — Round {{round}}

You are verifying that an implementation plan faithfully covers a design spec.

- Spec: `{{spec_path}}`
- Plan: `{{plan_path}}`

The current stage is `{{stage}}`.

## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.

## Other tasks in plan (for scope reference, NOT for review)

{{plan_task_headers}}

Use this list to recognize findings that belong to a different task than the one being reviewed. Those findings are out of scope.

Read both files. Then assess:

1. **Coverage** — every requirement, contract, or non-goal in the spec maps to either a task in the plan or an explicit out-of-scope note. List any gaps.
2. **Fidelity** — the plan's task code, file paths, and contracts match what the spec defines. Flag drifts (e.g., spec says `WENS_ORCHESTRATED`, plan checks a different variable).
3. **Placeholder scan** — TBDs, "TODO", "implement later", "similar to task N" without repeated code, references to undefined types/methods.
4. **Type/identifier consistency** — a function called `foo()` in task 3 must be `foo()` (not `fooBar()`) in task 7.
5. **Granularity** — each task is bite-sized (2–5 min steps), TDD-flavored where applicable, with exact paths and commands.

## Severity (CLOSED VOCABULARY)

Each issue MUST use exactly one of:
- `blocker` — would break correctness, security, or the acceptance gates.
- `major`   — substantive design or correctness problem, not blocking.
- `minor`   — style, naming, doc nit.

Do NOT invent other severities (no `medium`, `low`, `pass-note`, `nit`, etc.).

## Round Discipline

<!-- ROUND-1-BLOCK -->
(Round 1 — focused review)

Perform a focused review. Spot-check 3-5 load-bearing claims. Before emitting any finding, grep to verify the file/symbol/line actually exists.
<!-- /ROUND-1-BLOCK -->

<!-- R2-PLUS-BLOCK -->
(Round {{round}} — verify-only mode)

You are in **verify-only mode**. The previous-round issues are listed below under "R{{prev_round}} issues to verify". For each, confirm resolution: `resolved | unresolved | partially-resolved`. You MAY add NEW findings ONLY at severity `blocker`. Do NOT add `major` or `minor` findings — those wait for the next iteration.

### R{{prev_round}} issues to verify
{{r1_issues_inline}}
<!-- /R2-PLUS-BLOCK -->

## Output contract

Your response MUST begin with a YAML frontmatter block of the exact shape below.

```yaml
---
status: PASS | ISSUES_FOUND
issues:
  - severity: blocker | major | minor
    location: "<plan section or file:line>"
    description: "<what's wrong>"
    suggestion: "<concrete fix>"
---
```

- `PASS` requires zero blockers and zero majors.
- `issues: []` when PASS.
```

- [ ] **Step 4: Update `implement-task-prompt.md`** (add Scope Guard only — no Plan list, no Severity, no Round Discipline)

Read the current file. After the existing intro/contract section, find a natural location near the top of the prompt body and insert Block A. The exact final shape must contain a `## Scope Guard (MUST FOLLOW)` heading with the Block A text and `{{stage}}` placeholder. Do not remove any existing content.

Concretely, add the following block immediately after the opening header lines (line 1-3 region) of `implement-task-prompt.md`:

```markdown

The current stage is `{{stage}}`.

## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.
```

(Note: the `implement-task-prompt.md` is given to the implementer, not a reviewer. The Scope Guard wording still applies — implementer should not touch other tasks' files.)

- [ ] **Step 5: Update `spec-compliance-review-prompt.md`**

Read the current file. Insert all four blocks (A, B, C, D) at appropriate locations: A immediately after the intro paragraph that names `{{spec_path}}` or equivalent; B immediately after A; C inside the "Output contract" / severity section (replacing any existing severity wording); D between C and the YAML contract block. Use the exact text from Step 1 above. Preserve all existing review-criterion text (Coverage, Fidelity, etc.). The first line after the H1 should be `The current stage is \`{{stage}}\`.` and the final output contract YAML block should be unchanged.

- [ ] **Step 6: Update `code-review-prompt.md`**

Same procedure as Step 5 for `code-review-prompt.md`. All four blocks (A, B, C, D), preserving existing review criteria and the output contract.

- [ ] **Step 7: Verify**

Run all of these; each must exit 0:

```sh
test "$(rg -l 'Scope Guard \(MUST FOLLOW\)' skills/using-wens-superpowers/references/ | wc -l)" -eq 5
test "$(rg -l 'CLOSED VOCABULARY' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l '<!-- ROUND-1-BLOCK -->' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l '<!-- R2-PLUS-BLOCK -->' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l 'plan_task_headers' skills/using-wens-superpowers/references/ | wc -l)" -eq 3
test "$(rg -l '\{\{stage\}\}' skills/using-wens-superpowers/references/ | wc -l)" -eq 5
test "$(rg -l '\{\{prev_round\}\}' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l '\{\{r1_issues_inline\}\}' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
# spec-review and implement-task must NOT contain plan_task_headers
test "$(rg -l 'plan_task_headers' skills/using-wens-superpowers/references/spec-review-prompt.md 2>/dev/null | wc -l)" -eq 0
test "$(rg -l 'plan_task_headers' skills/using-wens-superpowers/references/implement-task-prompt.md 2>/dev/null | wc -l)" -eq 0
# implement-task must NOT contain CLOSED VOCABULARY or round blocks
test "$(rg -l 'CLOSED VOCABULARY|ROUND-1-BLOCK' skills/using-wens-superpowers/references/implement-task-prompt.md 2>/dev/null | wc -l)" -eq 0
```

- [ ] **Step 8: Commit**

```sh
git add skills/using-wens-superpowers/references/
git commit -m "feat(reviewer-templates): embed scope-guard, severity vocab, round discipline blocks"
```

---

## Task 4: Update `subagent-driven-development/SKILL.md` orchestrated section

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

Implements spec §6. This is the heaviest skill change.

- [ ] **Step 1: Locate the existing orchestrated branch**

Find the section in `skills/subagent-driven-development/SKILL.md` that begins with the gate text mentioning "running inside a `using-wens-superpowers` session" or `WENS_ORCHESTRATED`. This is the orchestrated branch. All changes in this task occur inside that branch (do not touch standard-mode content).

- [ ] **Step 2: Insert the "Mode (b) Cost Estimate" section (before TaskCreate)**

At the top of the orchestrated branch (before any per-task loop), insert verbatim:

```markdown
## Mode (b) Cost Estimate

Before TaskCreate (next section) and before the first dispatch in mode (b), count the plan tasks by scanning the plan file:

```sh
N=$(rg -c '^## Task ' <plan-file>)
```

Then surface to the user:

> 「將透過 agd dispatch N 個 tasks，每個 task 含 1 implementer + 2 reviewers = 3N 次 dispatch。預估 3N 次 agd 呼叫，不含 review 迭代。確認繼續嗎？」

Use `AskUserQuestion` with options: 繼續 / 中止 / 改用 mode (a).

On abort, no TaskCreate has yet been made, so no cleanup needed. On "改用 mode (a)" the main agent re-enters this section under mode (a), which skips this gate but still runs the TaskCreate mandate.

Mode (a) does not perform this gate. Ordering is therefore:
**plan in hand → cost-gate (mode b only) → TaskCreate → first dispatch.**
```

- [ ] **Step 3: Insert the TaskCreate mandate section (immediately after cost gate)**

```markdown
## Orchestrated Mode — Task Tracking (MANDATORY)

Once the cost estimate gate (mode b) returns "繼續" — or immediately in mode a — you MUST call `TaskCreate` once per plan task, using the plan's `## Task N:` header text as the task subject. This is not optional — the user cannot see your progress otherwise, and a context compaction loses your in-memory state.

Use exactly this sequence per task:

1. `TaskUpdate <id> status=in_progress` before dispatching the implementer (mode b) or before starting local implementation (mode a).
2. After spec-compliance review PASS: keep status `in_progress`.
3. After code review PASS: `TaskUpdate <id> status=completed`.
4. If either review returns ISSUES_FOUND: keep `in_progress` and iterate. Do NOT create sub-tasks per fix iteration — that explodes the list.

The previous wording referenced `TodoWrite`. That is the legacy name; use whatever the current harness exposes as `TaskCreate` / `TaskUpdate` / `TaskList`.
```

- [ ] **Step 4: Insert the "Tolerant Parsing of Reviewer Output" section**

Place this section near the existing reviewer-dispatch loop body, before the per-task dispatch sequence:

```markdown
## Tolerant Parsing of Reviewer Output

When reading reviewer `out.md`, apply in order:

1. If the body is wrapped in ```yaml ... ``` fences, strip them.
2. Parse the leading YAML frontmatter (between `---` lines).
3. If frontmatter is absent or unparseable: treat as `status: ISSUES_FOUND` with a single synthetic issue noting the format violation. Do NOT retry dispatch — proceed to fix-iteration with the body as freeform text.
4. For each issue's `severity`:
   - If in {blocker, major, minor}: accept as-is.
   - Otherwise (e.g. medium, low, nit, pass-note): coerce to `minor` and note the coercion to the user once per session.
```

- [ ] **Step 5: Insert the "Git Operations" section**

```markdown
## Git Operations in Orchestrated Mode

The dispatched implementer (mode b) decides its own commit boundary. Any additional commits the main agent creates (rare — typically only for finalization docs) MUST use:

    git add <specific-file>...
    git commit -m "..."

Do NOT use `git commit -am` or `git add -A`. The orchestrated session has generated artifacts in `docs/tmp/` (gitignored) plus working-tree changes from recently dispatched tasks — `-am` will sweep unrelated edits into the wrong commit.
```

- [ ] **Step 6: Update the existing reviewer-dispatch sub-section to render plan task headers + R-prev carry-over**

Within the existing per-task dispatch instructions in the orchestrated branch, locate where the main agent renders `spec-compliance-review-prompt.md` and `code-review-prompt.md`. Update / insert the rendering rules so they read (verbatim):

```markdown
For each reviewer dispatch:

- Populate `{{stage}}` with `task N` (where N is the current task number).
- Populate `{{plan_task_headers}}` with the output of:

  ```sh
  rg '^## Task ' <plan-file>
  ```

  If the plan path is not in `docs/superpowers/plans/`, fall back to the task subjects from `TaskList`.

- Populate `{{round}}` with the current round integer string (`"1"`, `"2"`, ...).

For each reviewer dispatch beyond round 1:

- Set `{{prev_round}}` = `{{round}} - 1` as an integer string.
- Read the previous out.md.
- Extract the YAML `issues:` list (use the tolerant parser above to read it).
- Inline-substitute into `{{r1_issues_inline}}` (despite the historical name, this carries the previous round's issues for any N ≥ 2).
- Strip the `<!-- ROUND-1-BLOCK -->...<!-- /ROUND-1-BLOCK -->` block from the rendered template; keep only the `<!-- R2-PLUS-BLOCK -->...<!-- /R2-PLUS-BLOCK -->` block.

For round-1 reviewer dispatches:

- Strip the `<!-- R2-PLUS-BLOCK -->...<!-- /R2-PLUS-BLOCK -->` block; keep only the `<!-- ROUND-1-BLOCK -->...<!-- /ROUND-1-BLOCK -->` block.
- Do not substitute `{{prev_round}}` or `{{r1_issues_inline}}` (the slots live only inside the R2+ block).
```

- [ ] **Step 7: Update any existing timeout / empty-output wording in the orchestrated branch**

Find any existing phrases like `WENS_DISPATCH_TIMEOUT=1200` or `on dispatch failure, retry once` in the orchestrated branch and replace with:

- Replace `set \`WENS_DISPATCH_TIMEOUT=1200\`` (or similar) with: `tier defaults apply (see \`scripts/dispatch.sh\`); set \`WENS_DISPATCH_TIMEOUT\` only to override.`
- Replace `on dispatch failure, retry once` (or similar) with: `\`dispatch.sh\` retries empty / no-frontmatter output internally; main agent handles only non-zero exit and post-retry failures.`

If those exact phrases don't exist, add the replacement text near the top of the orchestrated branch under a `### Behavior reference` sub-heading.

- [ ] **Step 8: Remove `TodoWrite` legacy references inside the orchestrated branch only**

Use `rg -n 'TodoWrite' skills/subagent-driven-development/SKILL.md` to find occurrences. Within the orchestrated branch, replace each occurrence with `TaskCreate / TaskUpdate / TaskList`. Outside the orchestrated branch, leave them untouched (those are the standard-mode pre-existing references — out of scope for this task).

If no `TodoWrite` mentions exist inside the orchestrated branch, that's fine — the TaskCreate mandate added in Step 3 already covers the new naming. Note in a code comment is not required.

- [ ] **Step 9: Verify**

```sh
rg -q 'TaskCreate' skills/subagent-driven-development/SKILL.md
rg -q 'Mode \(b\) Cost Estimate' skills/subagent-driven-development/SKILL.md
rg -q 'git add <specific-file>' skills/subagent-driven-development/SKILL.md
rg -q 'Tolerant Parsing' skills/subagent-driven-development/SKILL.md
rg -q 'coerce to `minor`' skills/subagent-driven-development/SKILL.md
rg -q 'ROUND-1-BLOCK' skills/subagent-driven-development/SKILL.md
rg -q 'R2-PLUS-BLOCK' skills/subagent-driven-development/SKILL.md
rg -q 'plan_task_headers' skills/subagent-driven-development/SKILL.md
rg -q 'AskUserQuestion' skills/subagent-driven-development/SKILL.md
rg -q 'tier defaults apply' skills/subagent-driven-development/SKILL.md
# Within the orchestrated branch, TodoWrite must not appear. Easiest broad check:
# (this checks the WHOLE file — verify manually if a standard-mode TodoWrite reference legitimately remains)
# test "$(rg 'TodoWrite' skills/subagent-driven-development/SKILL.md | wc -l)" -eq 0
```

The commented-out line is a weaker assertion — only assert zero `TodoWrite` if you confirmed no standard-mode references exist.

- [ ] **Step 10: Commit**

```sh
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(subagent-driven-development): orchestrated mode TaskCreate, cost gate, tolerant parse, git safety"
```

---

## Task 5: Update `brainstorming/SKILL.md` orchestrated section

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

Implements spec §7 for brainstorming.

- [ ] **Step 1: Locate orchestrated branch**

Find the `## Orchestrated Mode: Spec Review Loop` section (currently around step 7a).

- [ ] **Step 2: Replace timeout reference**

Find any literal mentioning `WENS_DISPATCH_TIMEOUT=600` (or any specific seconds value). Replace with:

```
Tier default is 900s (15 min) for spec-review; set `WENS_DISPATCH_TIMEOUT` only to override.
```

- [ ] **Step 3: Replace empty-output / retry wording**

Find any wording like "dispatch.sh non-zero exit ... Retry once" or "on second failure, surface to user". Replace the entire treatment with:

```markdown
`dispatch.sh` retries empty / no-frontmatter output internally (stderr will show `retry=1`). Main agent retries only on non-zero exit or post-retry format violation. On second failure surface to user via `AskUserQuestion`.
```

- [ ] **Step 4: Add R2+ rules paragraph**

Inside the orchestrated branch, after the round-loop description and before the round-10 gate, add:

```markdown
From round 2 onward, the template enforces verify-only mode: new findings allowed only at severity `blocker`. The main agent strips the `<!-- ROUND-1-BLOCK -->...<!-- /ROUND-1-BLOCK -->` from the rendered template and keeps only `<!-- R2-PLUS-BLOCK -->...<!-- /R2-PLUS-BLOCK -->`. R1 issues are passed inline via `{{r1_issues_inline}}` — main agent extracts the issues section from the previous out.md and substitutes before dispatch. `{{prev_round}}` substitutes to `{{round}} - 1` as integer string.
```

- [ ] **Step 5: Add tolerant parsing paragraph**

Immediately after the R2+ rules paragraph:

```markdown
Parse out.md leniently: strip ```yaml fences if present; treat non-{blocker,major,minor} severities as `minor`; missing frontmatter → `ISSUES_FOUND` with synthetic format-violation issue.
```

- [ ] **Step 6: Add "Behavior reference" block near orchestrated entry**

Insert near the top of the orchestrated branch (after the gate-text sentence, before the loop body):

```markdown
**Behavior reference.** The dispatch wrapper (`scripts/dispatch.sh`) handles timeout tiers, empty-output retry, and slug sanitization on its own. The reviewer prompt templates handle scope guard, severity vocabulary, and R2+ verify-only on their own. Main-agent responsibilities are limited to:

1. Rendering placeholders (`{{spec_path}}`, `{{stage}}`, `{{round}}`, `{{prev_round}}`, `{{r1_issues_inline}}`).
2. Stripping the unused round-block (Round-1 strips R2-PLUS-BLOCK; R2+ strips ROUND-1-BLOCK).
3. Parsing reviewer out.md (tolerant rules above).
4. Editing the spec file inline to apply confirmed findings.
5. Deciding loop exit (PASS) vs continue (ISSUES_FOUND).
6. Surfacing the round-10 gate via `AskUserQuestion`.
```

- [ ] **Step 7: Remove any `dispatch-agent` literal**

```sh
rg -n 'dispatch-agent' skills/brainstorming/SKILL.md
```

For each match, replace `dispatch-agent` with `agd`. If a match is in a code block referring to the old binary name in a worked example, the same substitution applies.

- [ ] **Step 8: Verify**

```sh
rg -q 'Tier default is 900s' skills/brainstorming/SKILL.md
rg -q 'verify-only mode' skills/brainstorming/SKILL.md
rg -q 'Behavior reference' skills/brainstorming/SKILL.md
rg -q 'coerce|coerce to' skills/brainstorming/SKILL.md || rg -q "treat non-\{blocker,major,minor\}" skills/brainstorming/SKILL.md
test "$(rg 'dispatch-agent' skills/brainstorming/SKILL.md | wc -l)" -eq 0
rg -q 'ROUND-1-BLOCK' skills/brainstorming/SKILL.md
rg -q 'r1_issues_inline' skills/brainstorming/SKILL.md
```

- [ ] **Step 9: Commit**

```sh
git add skills/brainstorming/SKILL.md
git commit -m "feat(brainstorming): orchestrated section uses new tiers, R2+ verify-only, tolerant parse"
```

---

## Task 6: Update `writing-plans/SKILL.md` orchestrated section

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

Implements spec §7 for writing-plans + §7.5 (plan task headers).

- [ ] **Step 1: Locate orchestrated branch**

Find the `## Orchestrated Mode: Plan Verification Loop` section.

- [ ] **Step 2: Replace timeout reference**

Find `WENS_DISPATCH_TIMEOUT=600` (or similar) and replace with:

```
Tier default is 1200s (20 min) for plan-verify; set `WENS_DISPATCH_TIMEOUT` only to override.
```

- [ ] **Step 3: Replace empty-output / retry wording**

Same replacement text as Task 5 Step 3.

- [ ] **Step 4: Add R2+ rules paragraph**

Same paragraph as Task 5 Step 4, but the verify target is the plan rather than the spec. The text is otherwise identical.

- [ ] **Step 5: Add tolerant parsing paragraph**

Same text as Task 5 Step 5.

- [ ] **Step 6: Add Behavior reference block**

Same as Task 5 Step 6 but adjusted for plan stage. Include `{{plan_path}}` in the placeholder list:

```markdown
**Behavior reference.** The dispatch wrapper (`scripts/dispatch.sh`) handles timeout tiers, empty-output retry, and slug sanitization on its own. The reviewer prompt templates handle scope guard, severity vocabulary, and R2+ verify-only on their own. Main-agent responsibilities are limited to:

1. Rendering placeholders (`{{spec_path}}`, `{{plan_path}}`, `{{stage}}`, `{{plan_task_headers}}`, `{{round}}`, `{{prev_round}}`, `{{r1_issues_inline}}`).
2. Stripping the unused round-block (Round-1 strips R2-PLUS-BLOCK; R2+ strips ROUND-1-BLOCK).
3. Parsing reviewer out.md (tolerant rules above).
4. Editing the plan file inline to apply confirmed findings.
5. Deciding loop exit (PASS) vs continue (ISSUES_FOUND).
6. Surfacing the round-10 gate via `AskUserQuestion`.
```

- [ ] **Step 7: Add plan task headers rendering rule**

Inside the orchestrated branch, add (near where the prompt-rendering step is described):

```markdown
When rendering `plan-verify-prompt.md`, populate `{{plan_task_headers}}` with the output of `rg '^## Task ' <plan-file>`. This gives the reviewer scope context (used in the scope guard block).
```

- [ ] **Step 8: Remove any `dispatch-agent` literal**

```sh
rg -n 'dispatch-agent' skills/writing-plans/SKILL.md
```

Replace each occurrence with `agd`.

- [ ] **Step 9: Verify**

```sh
rg -q 'Tier default is 1200s' skills/writing-plans/SKILL.md
rg -q 'verify-only mode' skills/writing-plans/SKILL.md
rg -q 'Behavior reference' skills/writing-plans/SKILL.md
rg -q 'plan_task_headers' skills/writing-plans/SKILL.md
rg -q "rg '\^## Task ' <plan-file>" skills/writing-plans/SKILL.md
test "$(rg 'dispatch-agent' skills/writing-plans/SKILL.md | wc -l)" -eq 0
rg -q 'r1_issues_inline' skills/writing-plans/SKILL.md
```

- [ ] **Step 10: Commit**

```sh
git add skills/writing-plans/SKILL.md
git commit -m "feat(writing-plans): orchestrated section uses new tiers, plan task headers, R2+ verify-only"
```

---

## Task 7: Run full acceptance gates + CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`
- Read: every file from Tasks 1-6 (for §9.1 gate run)

Implements spec §9.1 + §9.2 + §9.4 PR checklist + spec §10 (CHANGELOG entry per CLAUDE.md After Each Development Task).

- [ ] **Step 1: Run the full §9.1 grep gate suite (must all pass)**

```sh
set -e

# A. dispatch-agent legacy name removed (skills/ tree)
test "$(rg -n 'dispatch-agent' skills/ | wc -l)" -eq 0

# B. agd present in orchestrator
rg -q '`agd`' skills/using-wens-superpowers/SKILL.md

# C. dispatch.sh syntax + tokens (interpreter-matched: shebang is /bin/sh)
sh -n skills/using-wens-superpowers/scripts/dispatch.sh
rg -q 'TIER=' skills/using-wens-superpowers/scripts/dispatch.sh
rg -q 'retry=1 reason=' skills/using-wens-superpowers/scripts/dispatch.sh

# D. Reviewer template blocks
test "$(rg -l 'Scope Guard \(MUST FOLLOW\)' skills/using-wens-superpowers/references/ | wc -l)" -eq 5
test "$(rg -l 'CLOSED VOCABULARY' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l 'R2-PLUS-BLOCK' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l 'plan_task_headers' skills/using-wens-superpowers/references/ | wc -l)" -eq 3

# E. subagent-driven-development orchestrated section
rg -q 'TaskCreate' skills/subagent-driven-development/SKILL.md
rg -q 'git add <specific-file>' skills/subagent-driven-development/SKILL.md
rg -q 'Tolerant Parsing|coerce to `minor`' skills/subagent-driven-development/SKILL.md
rg -q 'AskUserQuestion' skills/subagent-driven-development/SKILL.md

# F. brainstorming & writing-plans references updated
test "$(rg -l 'Behavior reference' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md | wc -l)" -eq 2
test "$(rg -l 'verify-only mode' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md | wc -l)" -eq 2
rg -q 'plan_task_headers' skills/writing-plans/SKILL.md

# G. /tmp policy section present
rg -q 'system tmp' skills/using-wens-superpowers/SKILL.md

echo "all gates pass"
```

Expected final output: `all gates pass`. Any failure → fix the offending Task's content and re-run.

- [ ] **Step 2: Run the §9.2 dispatch.sh smoke (fake-agd)**

```sh
mkdir -p /tmp/fake-agd-bin
cat > /tmp/fake-agd.sh <<'EOF'
#!/usr/bin/env sh
state_file=/tmp/fake-agd-state
if [ -f "$state_file" ]; then
  printf -- '---\nstatus: PASS\nissues: []\n---\n'
else
  touch "$state_file"
  :
fi
EOF
chmod +x /tmp/fake-agd.sh
ln -sf /tmp/fake-agd.sh /tmp/fake-agd-bin/agd
rm -f /tmp/fake-agd-state

ORIG_PATH="$PATH"
PATH="/tmp/fake-agd-bin:$PATH"

echo "smoke" | sh skills/using-wens-superpowers/scripts/dispatch.sh spec-review-r1 2> /tmp/stderr.log
grep -q 'retry=1 reason=empty_output' /tmp/stderr.log
grep -q 'timeout=900 tier=spec-review' /tmp/stderr.log

rm -f /tmp/fake-agd-state
echo "smoke" | sh skills/using-wens-superpowers/scripts/dispatch.sh implement-task5 2> /tmp/stderr2.log
grep -q 'timeout=1800 tier=implement' /tmp/stderr2.log

PATH="$ORIG_PATH"
rm -rf /tmp/fake-agd-bin /tmp/fake-agd.sh /tmp/fake-agd-state /tmp/stderr.log /tmp/stderr2.log
echo "smoke OK"
```

Expected: `smoke OK`.

- [ ] **Step 3: Append CHANGELOG entry**

Read `CHANGELOG.md`. Locate the `## Unreleased` section (or create one at the top under the title if missing — preserve any existing entries below the section heading).

Append exactly this entry under `## Unreleased`:

```markdown
- **2026-05-20** — `using-wens-superpowers`: hard-switch wrapper from `dispatch-agent` to `agd`; add 4-tier timeout defaults (spec-review 15 min / plan-verify 20 min / implement 30 min / reviewer 15 min) with empty-output retry; embed scope-guard, severity vocab, and round-discipline blocks into reviewer templates; add TaskCreate mandate, mode (b) bypass probe + cost-gate ordering, tolerant YAML parsing, and `git add -am` safety to `subagent-driven-development`; document `/tmp/` vs `docs/tmp/` policy. Spec: `docs/superpowers/specs/2026-05-20-wens-orchestrator-optimization-design.md`. Plan: `docs/superpowers/plans/2026-05-20-wens-orchestrator-optimization.md`.
```

- [ ] **Step 4: Verify CHANGELOG**

```sh
rg -q '^## Unreleased' CHANGELOG.md
rg -q '2026-05-20 — `using-wens-superpowers`' CHANGELOG.md || rg -q "2026-05-20 .. \`using-wens-superpowers\`" CHANGELOG.md
```

If the smart-dash variant fails, accept the plain `--` or `-` form your editor produced — the gate is "an entry dated 2026-05-20 referencing using-wens-superpowers exists under Unreleased".

- [ ] **Step 5: Commit**

```sh
git add CHANGELOG.md
git commit -m "docs(changelog): add unreleased entry for wens-superpowers orchestrator round-2 optimization"
```

- [ ] **Step 6: Final acceptance attestation**

In your response to the user (or to the orchestrator), confirm:

- §9.1 grep gates all pass (Step 1 ran clean).
- §9.2 dispatch.sh smoke passes (Step 2 ran clean).
- §9.3 end-to-end smoke — manual reproducer documented in spec; the orchestrator handles e2e at PR-merge time (not part of this task).
- CHANGELOG entry appended.
- Spec §11 evaluation chapter present (no change required — already in spec).

---

## Out of scope (recap from spec §10.1)

These items appeared in source reflections but are NOT implemented by this plan:

- `wens-extract-task <N>` helper
- Token cost estimator with prices
- Task-type aware reviewer strictness
- Parallel spec-review and code-review
- Implementer + self-review combined
- Reviewer fed sub-sections of spec/plan
- Task body via reference (not inline)
- Helper "grep status only, print body on ISSUES_FOUND"
- `dispatch.sh` JSON stderr
- `--strict-output` / `--severity-vocabulary` flags
- Round-counter metadata, `--round N` flag
- Cancel / resume support
- `dispatch-agent` backward compatibility (hard switch)
- Dispatched spec/plan writing (evaluated in spec §11, recommendation: not now)
- Auto-cleanup of `docs/tmp/` at session end

If a reviewer flags any of these, mark out-of-scope and continue.
