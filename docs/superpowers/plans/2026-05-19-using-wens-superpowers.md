# using-wens-superpowers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `using-wens-superpowers` skill that orchestrates the standard brainstorm → plan → implement flow with externally-dispatched verification rounds via `dispatch-agent`, gated by `WENS_ORCHESTRATED` environment variable so upstream skill behavior is preserved when the orchestrator is not active.

**Architecture:** A thin orchestrator skill at `skills/using-wens-superpowers/` sets `WENS_ORCHESTRATED=1` and `WENS_MODE=a|b`, then invokes `brainstorming`. The forked `brainstorming`, `writing-plans`, and `subagent-driven-development` skills each check the marker and, when set, branch into a dispatch-agent-driven loop (spec review / plan verification / per-task implementer+reviewer dispatch) before auto-chaining to the next stage. A shared `scripts/dispatch.sh` wraps `dispatch-agent dispatch -f` with timeout, PATH guard, and prompt/output artifact capture in `docs/tmp/`. Prompt templates live in `references/`; the main agent renders `{{placeholders}}` inline (no sed/script). Reviewer output uses a YAML frontmatter contract (`status: PASS | ISSUES_FOUND`) parsed by the main agent.

**Tech Stack:** POSIX shell (`sh`/`bash`), Markdown skill files, `dispatch-agent` CLI (assumed on PATH).

---

## Spec Reference

Authoritative spec: `/Volumes/Home/Users/wen/.local/share/agm/source/myskills/docs/superpowers/specs/2026-05-19-using-wens-superpowers-design.md`

Spec was reviewed (round 1, `myskills/docs/tmp/20260519T061304Z-spec-review-r1.out.md`). The two blockers (Skill-tool auto-chain interception) are resolved by the new architecture: we fork the upstream skills and add a gated branch, so auto-chain is preserved and review is injected *inside* the existing chain. Remaining major/minor resolutions adopted in this plan:

| Issue | Resolution |
|---|---|
| Rendering mechanism contradiction | Inline by main agent — main agent reads template, substitutes `{{placeholders}}` in its own context, writes rendered prompt to `docs/tmp/`. No sed, no script. |
| `dispatch.sh` lacks timeout | `dispatch.sh` always passes `--timeout $WENS_DISPATCH_TIMEOUT` to `dispatch-agent`. Default 600s for review phases, 1200s for implement (set per-call by main agent before invocation). |
| Non-zero exit handling | `dispatch.sh` exits with `dispatch-agent`'s exit code. Main agent treats non-zero (including timeout) as `ISSUES_FOUND` with a synthetic issue containing the stderr tail. Retries once; on second failure, `AskUserQuestion`. |
| Stage 5 "single pass" contradiction | Drop "single pass". Same loop as spec review; 10-round `AskUserQuestion` gate applies. |
| "dispatch" terminology overload | Reserved: "dispatch" = `dispatch-agent` CLI; Task-tool calls = "invoke subagent". |
| Relationship to SDD internal reviewer prompts | When `WENS_ORCHESTRATED=1`, SDD's internal `spec-reviewer-prompt.md` and `code-quality-reviewer-prompt.md` are **bypassed** in favor of `dispatch-agent` calls using the orchestrator's `references/*-prompt.md`. Stated explicitly in SDD SKILL.md. |
| 10-round counter scope | Per-task. Reset when a new task begins. Spec review and plan verify each have their own counter, reset at stage entry. |
| Timestamp collisions | Filename pattern `<UTC-ts>-<slug>` is unique because slugs are unique within a stage. `dispatch.sh` adds `_$$` (pid) suffix as belt-and-suspenders. |
| `.gitignore` trailing newline | `dispatch.sh` (and orchestrator entry) ensure trailing newline before appending. |
| `dispatch-agent` PATH guard | `dispatch.sh` checks `command -v dispatch-agent` at startup; on miss, prints install hint to stderr and exits 127. |
| Redundant tee | `dispatch.sh` writes `dispatch-agent` stdout to `$OUT` only; main process stdout to `/dev/null`. Main agent reads `$OUT` via Read tool. |
| `files_changed` completeness (mode b) | After implementer returns COMPLETED, main agent runs `git diff --name-only HEAD` and merges results into `files_changed` before rendering reviewer prompts. |
| Marker propagation mechanism (round-2) | `WENS_ORCHESTRATED` is **not** propagated via shell env vars (Bash tool calls have independent shells in Claude Code — env exports do not persist). The marker is carried by the main agent's context: the orchestrator invokes `brainstorming` via the Skill tool, and the agent remembers it is running inside an orchestrated session. The SKILL.md gate text in `brainstorming` / `writing-plans` / `subagent-driven-development` says "When running inside a `using-wens-superpowers` session" rather than "When `WENS_ORCHESTRATED=1` is set in the shell environment". For `dispatch.sh`, `WENS_DISPATCH_TIMEOUT` (and any other per-call env var) is supplied by prefixing each Bash invocation. |
| `plan-verify-prompt.md` `{{round}}` placeholder (round-2) | Plan adds `{{round}}` to the template header (not in spec §7 table). Deliberate, parallel to `spec-review-prompt.md`. Rendering follows the same inline-substitution rule. |
| `plan-verify` slug suffixing (round-2) | Plan uses `plan-verify-r<N>` for **all** rounds (including round 1), not the spec §6 "bare for r1, suffixed on retry" pattern. Deliberate deviation for consistency with `spec-review-r<N>`. Tests in Task 3 also use the round-1 bare `plan-verify`; both forms are accepted by `dispatch.sh` (the slug is opaque). |

---

## File Structure

### New files (`skills/using-wens-superpowers/`)

| File | Responsibility |
|---|---|
| `SKILL.md` | Thin orchestrator. Entry checks (`.gitignore`, dispatch-agent presence), `AskUserQuestion` for mode (a/b), exports env vars, invokes `brainstorming` via Skill tool. |
| `scripts/dispatch.sh` | POSIX shell wrapper around `dispatch-agent dispatch -f`. Reads prompt from stdin, writes prompt + output artifacts to `docs/tmp/`, applies timeout, guards PATH. |
| `references/spec-review-prompt.md` | Template for Stage 3 spec review. Placeholders: `{{spec_path}}`, `{{round}}`. |
| `references/plan-verify-prompt.md` | Template for Stage 5 plan/spec consistency check. Placeholders: `{{spec_path}}`, `{{plan_path}}`, `{{round}}`. |
| `references/implement-task-prompt.md` | Mode (b) implementer template. Placeholders: `{{spec_path}}`, `{{plan_path}}`, `{{task_body}}`, `{{repo_root}}`. |
| `references/spec-compliance-review-prompt.md` | Per-task spec compliance review template. Placeholders: `{{spec_path}}`, `{{task_body}}`, `{{files_changed}}`. |
| `references/code-review-prompt.md` | Per-task code review template. Placeholders: `{{plan_path}}`, `{{task_body}}`, `{{files_changed}}`. |

### Modified files

| File | Change |
|---|---|
| `skills/brainstorming/SKILL.md` | Insert a "When `WENS_ORCHESTRATED=1`" block between checklist step 7 (Spec self-review) and step 8 (User reviews written spec). Block describes the spec-review dispatch loop. Auto-chain to writing-plans preserved. |
| `skills/writing-plans/SKILL.md` | Insert a "When `WENS_ORCHESTRATED=1`" block between Self-Review and Execution Handoff. Block describes plan-verify dispatch loop. Auto-chain (Execution Handoff) preserved with note that orchestrated mode auto-selects subagent-driven-development. |
| `skills/subagent-driven-development/SKILL.md` | Add an "When `WENS_ORCHESTRATED=1`" section describing per-task branching: mode (b) dispatches implementer; both modes dispatch reviewers via `dispatch-agent` using orchestrator's prompt templates (not the in-skill `spec-reviewer-prompt.md` / `code-quality-reviewer-prompt.md`). Define 10-round per-task gate. |
| `.gitignore` | Append `docs/tmp/` (with trailing-newline guard handled by orchestrator/dispatch.sh on first invocation; static append here for cleanliness). |
| `CHANGELOG.md` | Single Unreleased entry at end of plan execution (locked decision: one entry per feature, not per task). |

### Test artifacts (temporary, gitignored)

`tests/using-wens-superpowers/` — shell test scripts validating `dispatch.sh` behavior. These are part of this plan's deliverables and committed; they exercise the wrapper with a mock `dispatch-agent` on `PATH`.

---

## Branching

Per locked decision: develop directly on `main`. No feature branch. Periodically `git pull upstream main` between tasks (manual). Each task ends with a focused commit on `main`.

---

## Task 1: Add `docs/tmp/` to `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Confirm current state**

Run: `grep -nE '^docs/tmp/?$' .gitignore || echo "NOT PRESENT"`
Expected: `NOT PRESENT`

- [ ] **Step 2: Verify trailing newline in current `.gitignore`**

Run: `tail -c 1 .gitignore | od -c | head -1`
Expected: shows `\n` as the last byte. If not, the edit below must prepend a newline.

- [ ] **Step 3: Append `docs/tmp/` line**

Edit `.gitignore` by appending the following line at end of file:

```
docs/tmp/
```

- [ ] **Step 4: Verify the entry is present and the file ends with newline**

Run: `grep -nE '^docs/tmp/$' .gitignore && tail -c 1 .gitignore | od -c | head -1`
Expected: line number printed for the match; final byte is `\n`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore docs/tmp/ for dispatch-agent artifacts"
```

---

## Task 2: Skeleton `using-wens-superpowers` skill directory

**Files:**
- Create: `skills/using-wens-superpowers/SKILL.md` (stub — full content in Task 8)
- Create: `skills/using-wens-superpowers/scripts/.gitkeep`
- Create: `skills/using-wens-superpowers/references/.gitkeep`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p skills/using-wens-superpowers/scripts skills/using-wens-superpowers/references
touch skills/using-wens-superpowers/scripts/.gitkeep skills/using-wens-superpowers/references/.gitkeep
```

- [ ] **Step 2: Write SKILL.md stub**

Write `skills/using-wens-superpowers/SKILL.md`:

```markdown
---
name: using-wens-superpowers
description: "Orchestrates the superpowers brainstorm → plan → implement flow with dispatch-agent-driven external review at each stage. Use when starting a feature that warrants the full spec/plan/implement cycle and you want to offload review (and optionally implementation) to a third-party agent CLI."
---

# using-wens-superpowers

(Stub — full content added in Task 8 after dependencies exist.)
```

- [ ] **Step 3: Verify**

Run: `ls -la skills/using-wens-superpowers/ skills/using-wens-superpowers/scripts/ skills/using-wens-superpowers/references/`
Expected: directory tree with SKILL.md, two .gitkeep placeholders.

- [ ] **Step 4: Commit**

```bash
git add skills/using-wens-superpowers/
git commit -m "feat(using-wens-superpowers): create skill directory skeleton"
```

---

## Task 3: Write failing tests for `dispatch.sh`

**Files:**
- Create: `tests/using-wens-superpowers/run-dispatch-tests.sh`
- Create: `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-success.sh`
- Create: `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-fail.sh`
- Create: `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-slow.sh`

- [ ] **Step 1: Create test directory**

```bash
mkdir -p tests/using-wens-superpowers/fixtures
```

- [ ] **Step 2: Write the mock `dispatch-agent` success fixture**

Write `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-success.sh`:

```sh
#!/bin/sh
# Mock dispatch-agent: prints a canned PASS reviewer response.
# Accepts `dispatch -f <file> [--timeout N]` argv shape.
while [ $# -gt 0 ]; do
  case "$1" in
    -f) shift; PROMPT_FILE="$1"; shift ;;
    *) shift ;;
  esac
done
cat <<'OUT'
---
status: PASS
issues: []
---
OK from mock.
OUT
exit 0
```

```bash
chmod +x tests/using-wens-superpowers/fixtures/mock-dispatch-agent-success.sh
```

- [ ] **Step 3: Write the mock `dispatch-agent` failure fixture**

Write `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-fail.sh`:

```sh
#!/bin/sh
echo "simulated dispatch-agent failure" >&2
echo "partial output line" 
exit 42
```

```bash
chmod +x tests/using-wens-superpowers/fixtures/mock-dispatch-agent-fail.sh
```

- [ ] **Step 4: Write the mock `dispatch-agent` slow fixture (for timeout)**

Write `tests/using-wens-superpowers/fixtures/mock-dispatch-agent-slow.sh`:

```sh
#!/bin/sh
# Sleeps longer than the test timeout to verify timeout propagation.
sleep 5
echo "should not reach here"
```

```bash
chmod +x tests/using-wens-superpowers/fixtures/mock-dispatch-agent-slow.sh
```

- [ ] **Step 5: Write the test runner**

Write `tests/using-wens-superpowers/run-dispatch-tests.sh`:

```sh
#!/bin/sh
# Test runner for skills/using-wens-superpowers/scripts/dispatch.sh
# Uses a mock dispatch-agent on PATH for each test case.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$REPO_ROOT/skills/using-wens-superpowers/scripts/dispatch.sh"
TMPDIR_TEST="$(mktemp -d)"
PASS=0
FAIL=0

assert() {
  desc="$1"; shift
  if "$@"; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc"; FAIL=$((FAIL+1))
  fi
}

cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

# --- Test 1: missing dispatch-agent prints install hint and exits 127
run_test_missing_path() {
  cd "$TMPDIR_TEST" || return 1
  out=$(PATH="/usr/bin:/bin" sh "$DISPATCH" test-slug <<< "hello" 2>&1)
  rc=$?
  [ "$rc" = "127" ] && echo "$out" | grep -qi "dispatch-agent"
}
assert "missing dispatch-agent → exit 127 with hint" run_test_missing_path

# --- Test 2: success path writes prompt + .out.md, exit 0
run_test_success() {
  workdir="$TMPDIR_TEST/repo1"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin1"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-success.sh" "$bindir/dispatch-agent"
  PATH="$bindir:$PATH" sh "$DISPATCH" spec-review-r1 <<< "the prompt body" > /dev/null 2>"$workdir/stderr.log"
  rc=$?
  [ "$rc" = "0" ] || return 1
  prompt_file=$(grep -o 'prompt=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  out_file=$(grep -o 'out=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  [ -f "$prompt_file" ] && [ -f "$out_file" ] \
    && grep -q "the prompt body" "$prompt_file" \
    && grep -q "status: PASS" "$out_file"
}
assert "success → prompt + out files created, exit 0" run_test_success

# --- Test 3: dispatch-agent failure propagates exit code, partial output captured
run_test_failure() {
  workdir="$TMPDIR_TEST/repo2"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin2"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-fail.sh" "$bindir/dispatch-agent"
  PATH="$bindir:$PATH" sh "$DISPATCH" plan-verify <<< "anything" > /dev/null 2>"$workdir/stderr.log"
  rc=$?
  [ "$rc" = "42" ] || return 1
  out_file=$(grep -o 'out=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  [ -f "$out_file" ] && grep -q "partial output line" "$out_file"
}
assert "failure → exit code propagates, partial out captured" run_test_failure

# --- Test 4: timeout flag is passed through
run_test_timeout_flag() {
  workdir="$TMPDIR_TEST/repo3"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin3"
  mkdir -p "$bindir"
  # Mock that records its argv to a file then prints PASS
  cat > "$bindir/dispatch-agent" <<EOF
#!/bin/sh
echo "ARGV: \$*" > "$workdir/argv.log"
echo "---"
echo "status: PASS"
echo "issues: []"
echo "---"
EOF
  chmod +x "$bindir/dispatch-agent"
  WENS_DISPATCH_TIMEOUT=42 PATH="$bindir:$PATH" sh "$DISPATCH" spec-review-r1 <<< "x" > /dev/null 2>"$workdir/stderr.log"
  grep -q -- "--timeout 42" "$workdir/argv.log"
}
assert "WENS_DISPATCH_TIMEOUT → passed as --timeout to dispatch-agent" run_test_timeout_flag

# --- Test 5: docs/tmp/ created lazily
run_test_lazy_mkdir() {
  workdir="$TMPDIR_TEST/repo4"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin4"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-success.sh" "$bindir/dispatch-agent"
  [ -d "$workdir/docs/tmp" ] && return 1  # must not exist yet
  PATH="$bindir:$PATH" sh "$DISPATCH" plan-verify <<< "x" > /dev/null 2>"$workdir/stderr.log"
  [ -d "$workdir/docs/tmp" ]
}
assert "docs/tmp/ created lazily on first call" run_test_lazy_mkdir

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
```

```bash
chmod +x tests/using-wens-superpowers/run-dispatch-tests.sh
```

- [ ] **Step 6: Run tests to confirm they fail (dispatch.sh does not yet exist)**

Run: `tests/using-wens-superpowers/run-dispatch-tests.sh`
Expected: all 5 tests FAIL (dispatch.sh missing).

- [ ] **Step 7: Commit failing tests**

```bash
git add tests/using-wens-superpowers/
git commit -m "test(using-wens-superpowers): add dispatch.sh shell tests (failing)"
```

---

## Task 4: Implement `dispatch.sh`

**Files:**
- Create: `skills/using-wens-superpowers/scripts/dispatch.sh`
- Remove: `skills/using-wens-superpowers/scripts/.gitkeep`

- [ ] **Step 1: Write `dispatch.sh`**

Write `skills/using-wens-superpowers/scripts/dispatch.sh`:

```sh
#!/bin/sh
# dispatch.sh — wraps `dispatch-agent dispatch -f` for using-wens-superpowers.
# Reads prompt from stdin; writes prompt + .out.md to docs/tmp/<ts>_<pid>-<slug>.
# Emits `prompt=...` and `out=...` on stderr. Exit code mirrors dispatch-agent
# (127 if not on PATH, 2 if argv malformed). $WENS_DISPATCH_TIMEOUT (default 600).

set -u

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "dispatch.sh: missing <phase-slug> argument" >&2
  echo "usage: cat prompt.md | dispatch.sh <phase-slug>" >&2
  exit 2
fi

if ! command -v dispatch-agent >/dev/null 2>&1; then
  echo "dispatch.sh: 'dispatch-agent' not found on PATH." >&2
  echo "  Install it (https://github.com/superyngo/dispatch-agent or equivalent)" >&2
  echo "  and ensure it is on \$PATH before re-running." >&2
  exit 127
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TMPDIR_ABS="$REPO_ROOT/docs/tmp"
mkdir -p "$TMPDIR_ABS"

TS=$(date -u +%Y%m%dT%H%M%SZ)
BASE="${TS}_$$-${SLUG}"
PROMPT="$TMPDIR_ABS/${BASE}.md"
OUT="$TMPDIR_ABS/${BASE}.out.md"

cat > "$PROMPT"
echo "prompt=$PROMPT" >&2
echo "out=$OUT" >&2

TIMEOUT="${WENS_DISPATCH_TIMEOUT:-600}"
dispatch-agent dispatch -f "$PROMPT" --timeout "$TIMEOUT" > "$OUT" 2>>"$OUT"
exit $?
```

```bash
chmod +x skills/using-wens-superpowers/scripts/dispatch.sh
rm skills/using-wens-superpowers/scripts/.gitkeep
```

- [ ] **Step 2: Run tests to confirm they pass**

Run: `tests/using-wens-superpowers/run-dispatch-tests.sh`
Expected: `Results: 5 passed, 0 failed`. If any test fails, fix the script and re-run before proceeding.

- [ ] **Step 3: Sanity-check line count**

Run: `wc -l skills/using-wens-superpowers/scripts/dispatch.sh`
Expected: ≤ 45 lines (spec §11.6 target ~40; +5 budget for PATH guard).

- [ ] **Step 4: Commit**

```bash
git add skills/using-wens-superpowers/scripts/
git commit -m "feat(using-wens-superpowers): add dispatch.sh wrapper for dispatch-agent"
```

(`.gitkeep` was deleted; staging the directory captures both the new file and the deletion in one commit.)

---

## Task 5: Write prompt templates

**Files:**
- Create: `skills/using-wens-superpowers/references/spec-review-prompt.md`
- Create: `skills/using-wens-superpowers/references/plan-verify-prompt.md`
- Create: `skills/using-wens-superpowers/references/implement-task-prompt.md`
- Create: `skills/using-wens-superpowers/references/spec-compliance-review-prompt.md`
- Create: `skills/using-wens-superpowers/references/code-review-prompt.md`
- Remove: `skills/using-wens-superpowers/references/.gitkeep`

All templates share an "Output contract" footer reminding the third-party agent to begin its response with a YAML frontmatter block. Placeholders use `{{name}}` and are substituted by the main agent (not by sed).

- [ ] **Step 1: Write `spec-review-prompt.md`**

Write `skills/using-wens-superpowers/references/spec-review-prompt.md`:

```markdown
# Spec Review — Round {{round}}

You are reviewing a design spec for a software feature. The spec lives at:

`{{spec_path}}`

Read it carefully and assess whether it is implementation-ready. Focus on:

1. **Completeness** — are all decisions made, or are there TBDs / open questions left implicit?
2. **Consistency** — do sections contradict each other? Do statements about behavior, file layout, and contracts agree?
3. **Implementability** — could a skilled engineer hand this to a fresh team without further clarification? Are there hidden assumptions about the runtime, tools, or environment?
4. **Scope** — is the scope coherent, or does it bundle independent subsystems that should be split?
5. **Risks** — are tradeoffs surfaced, with mitigations or accepted-risk statements?

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

- [ ] **Step 2: Write `plan-verify-prompt.md`**

Write `skills/using-wens-superpowers/references/plan-verify-prompt.md`:

```markdown
# Plan vs. Spec Consistency Check — Round {{round}}

You are verifying that an implementation plan faithfully covers a design spec.

- Spec: `{{spec_path}}`
- Plan: `{{plan_path}}`

Read both files. Then assess:

1. **Coverage** — every requirement, contract, or non-goal in the spec maps to either a task in the plan or an explicit out-of-scope note. List any gaps.
2. **Fidelity** — the plan's task code, file paths, and contracts match what the spec defines. Flag drifts (e.g., spec says `WENS_ORCHESTRATED`, plan checks a different variable).
3. **Placeholder scan** — TBDs, "TODO", "implement later", "similar to task N" without repeated code, references to undefined types/methods.
4. **Type/identifier consistency** — a function called `foo()` in task 3 must be `foo()` (not `fooBar()`) in task 7.
5. **Granularity** — each task is bite-sized (2–5 min steps), TDD-flavored where applicable, with exact paths and commands.

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

- [ ] **Step 3: Write `implement-task-prompt.md`**

Write `skills/using-wens-superpowers/references/implement-task-prompt.md`:

```markdown
# Implement Task (Mode b — dispatched implementer)

You are implementing one task from an approved implementation plan. The main coordinator is running on a separate session and has delegated this task to you via `dispatch-agent`.

**Workspace root:** `{{repo_root}}`
**Spec:** `{{spec_path}}`
**Plan:** `{{plan_path}}`

## Task to implement

{{task_body}}

## Rules

1. Work directly in `{{repo_root}}`. You may write files. (Your `dispatch-agent` config has bypass flags enabled by the operator.)
2. Follow the task's TDD steps exactly: write failing test → run it → implement → run again → commit.
3. Do NOT modify files outside the paths the task lists, unless the task says to.
4. Do NOT skip the commit step. Use the commit message shown in the task verbatim.
5. If a step is ambiguous or you discover the plan is wrong, STOP and emit `status: BLOCKED` with notes.
6. Run only the commands the task lists. If you must run other commands (e.g., to inspect state), do so but do not let them mutate the workspace.

## Output contract

Your response MUST **conclude with** the following YAML status block (a literal `---`-delimited block at the end of your message; this is NOT YAML frontmatter — progress notes come first, status block comes last):

```yaml
---
status: COMPLETED | BLOCKED
files_changed:
  - <path relative to {{repo_root}}>
notes: |
  <free-text summary; required even when COMPLETED>
---
```

- `COMPLETED`: all task steps executed, tests pass, commit created.
- `BLOCKED`: explain in `notes` what stopped you (missing context, plan conflict, environment).
- `files_changed` must list every file you created or modified. If you are unsure, run `git diff --name-only HEAD` and include the output.
```

- [ ] **Step 4: Write `spec-compliance-review-prompt.md`**

Write `skills/using-wens-superpowers/references/spec-compliance-review-prompt.md`:

```markdown
# Spec Compliance Review (per-task)

You are reviewing whether a just-implemented task matches the design spec.

- Spec: `{{spec_path}}`

## Task that was implemented

{{task_body}}

## Files the implementer touched

{{files_changed}}

## Your job

Compare the actual changes in those files to what the spec requires for this task. Specifically:

1. **Coverage** — every behavior the spec requires for this slice is present.
2. **No extras** — the implementation does not add features, flags, or behavior beyond the spec/task.
3. **Contracts** — output formats, env vars, file paths, exit codes match the spec exactly.
4. **No fabrication** — the implementer did not invent functionality that the spec did not call for.

Read the files via your filesystem tools (the dispatched agent has read access to `{{spec_path}}` and the files listed in `files_changed`). Do not rely on commit messages alone.

## Output contract

Begin your response with a YAML frontmatter block:

```yaml
---
status: PASS | ISSUES_FOUND
issues:
  - severity: blocker | major | minor
    location: "<file:line or behavior name>"
    description: "<gap or extra>"
    suggestion: "<concrete fix>"
---
```

- `PASS` only when zero blockers and zero majors.
- `issues: []` when PASS.
```

- [ ] **Step 5: Write `code-review-prompt.md`**

Write `skills/using-wens-superpowers/references/code-review-prompt.md`:

```markdown
# Code Quality Review (per-task)

You are reviewing the *quality* of a just-implemented task. Spec compliance has already been verified separately — focus on engineering quality.

- Plan: `{{plan_path}}`

## Task that was implemented

{{task_body}}

## Files the implementer touched

{{files_changed}}

## What to evaluate

1. **Correctness** — does the code do what it claims? Are edge cases handled the task called for? (Do not invent edge cases the task did not require.)
2. **Tests** — failing-then-passing TDD followed? Tests assert behavior, not implementation details? Are they runnable as-written?
3. **Clarity** — naming, structure, comments. Is there commentary that explains *why* for non-obvious code? No unnecessary noise?
4. **Surgical changes** — did the implementer touch only what the task required, or did they "improve" adjacent code?
5. **Idioms** — does the change match the surrounding codebase's style?

## Output contract

Begin with a YAML frontmatter block:

```yaml
---
status: PASS | ISSUES_FOUND
issues:
  - severity: blocker | major | minor
    location: "<file:line>"
    description: "<what's wrong>"
    suggestion: "<concrete fix>"
---
```

- `PASS` only when zero blockers and zero majors.
- Minor-only findings are acceptable; the main agent will surface them but will not loop.
```

- [ ] **Step 6: Remove placeholder, verify templates exist**

```bash
rm skills/using-wens-superpowers/references/.gitkeep
ls skills/using-wens-superpowers/references/
```

Expected: 5 `*.md` files, no `.gitkeep`.

- [ ] **Step 7: Commit**

```bash
git add skills/using-wens-superpowers/references/
git commit -m "feat(using-wens-superpowers): add dispatch-agent prompt templates"
```

---

## Task 6: Modify `brainstorming` to add `WENS_ORCHESTRATED` spec-review loop

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

The new block is inserted between checklist step 7 (Spec self-review) and step 8 (User reviews written spec). It describes the dispatched spec-review loop. Auto-chain to writing-plans is preserved.

- [ ] **Step 1: Re-read current `skills/brainstorming/SKILL.md`**

Run: `wc -l skills/brainstorming/SKILL.md`
Expected: ~165 lines (current).

- [ ] **Step 2: Edit the checklist to insert orchestrated-mode step 7.5**

In `skills/brainstorming/SKILL.md`, locate the checklist:

```
7. **Spec self-review** — quick inline check for placeholders, contradictions, ambiguity, scope (see below)
8. **User reviews written spec** — ask user to review the spec file before proceeding
```

Replace with:

```
7. **Spec self-review** — quick inline check for placeholders, contradictions, ambiguity, scope (see below)
7a. **(Orchestrated mode only)** If `WENS_ORCHESTRATED=1`, run the external spec-review loop (see "Orchestrated Mode: Spec Review Loop" section below) before step 8.
8. **User reviews written spec** — ask user to review the spec file before proceeding
```

- [ ] **Step 3: Append the orchestrated-mode section**

Append the following section to `skills/brainstorming/SKILL.md` (after the existing "Visual Companion" section):

```markdown
## Orchestrated Mode: Spec Review Loop

When the agent is running inside a `using-wens-superpowers` session (the orchestrator skill loaded this skill via auto-chain and declared `WENS_ORCHESTRATED=1` + `WENS_MODE=a|b` at session entry — the marker is carried by agent context, **not** by shell environment variables, since Bash tool calls do not share shells), perform an external spec-review loop after the inline self-review and **before** asking the user to review the spec.

**Loop body, round N (starts at 1, resets each fresh entry to brainstorming):**

1. Render `skills/using-wens-superpowers/references/spec-review-prompt.md` by substituting `{{spec_path}}` (absolute) and `{{round}}` (`N`). Substitute inline — read the template with the Read tool, perform string substitution in your own context, do not run `sed`.
2. Pipe the rendered prompt to `skills/using-wens-superpowers/scripts/dispatch.sh spec-review-r$N` via stdin. Set `WENS_DISPATCH_TIMEOUT=600` for this call.
3. The Bash tool's stderr output will contain `prompt=<path>` and `out=<path>` lines. Parse them. Then Read the `out=<path>` file.
4. Parse the leading YAML frontmatter for `status`.
   - `status: PASS` → exit loop, proceed to user-review (step 8).
   - `status: ISSUES_FOUND` → for each issue, edit the spec file inline (you, the main agent, do the rewrites — do NOT dispatch them). Increment `N`. Repeat.
   - Frontmatter missing or malformed → treat as `ISSUES_FOUND` with a synthetic issue noting the format violation. Re-dispatch with a stricter reminder appended to the rendered prompt.
   - `dispatch.sh` non-zero exit (including timeout) → treat as `ISSUES_FOUND` with a synthetic issue containing the stderr tail. Retry once. On second failure, surface to user via `AskUserQuestion`.
5. **Round 10 gate:** if `N` reaches 10 without `PASS`, use `AskUserQuestion` to ask the user: continue (resets counter, allows another 10), pause (return control), or accept-as-is (treat as PASS). Do not loop past 10 without user direction.

**Auto-chain unchanged.** After the user-review gate (step 8) approves, continue to step 9 (invoke writing-plans) exactly as in standard mode.

**Why this lives in brainstorming, not in `using-wens-superpowers`:** the auto-chain (`writing-plans` → `subagent-driven-development`) carries the marker through, so each downstream skill checks `WENS_ORCHESTRATED` and runs its own orchestrated branch. The orchestrator skill only sets the marker and invokes brainstorming; the chain does the rest.
```

- [ ] **Step 4: Verify the edit by greppi for the new section**

Run: `grep -nE 'Orchestrated Mode: Spec Review Loop|WENS_ORCHESTRATED' skills/brainstorming/SKILL.md`
Expected: at least 3 matches (checklist step 7a, section heading, environment variable references).

- [ ] **Step 5: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat(brainstorming): add WENS_ORCHESTRATED-gated spec-review dispatch loop"
```

---

## Task 7: Modify `writing-plans` to add `WENS_ORCHESTRATED` plan-verify loop

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

The new block runs between the existing "Self-Review" section and "Execution Handoff". Auto-chain is preserved; when orchestrated, the Execution Handoff auto-selects subagent-driven-development without prompting the user.

- [ ] **Step 1: Append the orchestrated-mode section**

In `skills/writing-plans/SKILL.md`, locate the `## Execution Handoff` heading. Insert the following new section **before** it:

```markdown
## Orchestrated Mode: Plan Verification Loop

When the agent is running inside a `using-wens-superpowers` session (orchestrated mode — marker is in agent context, not in shell env), run an external plan-vs-spec consistency check after Self-Review and **before** the Execution Handoff. Same loop shape as brainstorming's spec-review loop.

**Round N (starts at 1):**

1. Render `skills/using-wens-superpowers/references/plan-verify-prompt.md` by substituting `{{spec_path}}` (absolute), `{{plan_path}}` (absolute), and `{{round}}` (`N`). Inline substitution by the main agent — no `sed`.
2. Pipe the rendered prompt to `skills/using-wens-superpowers/scripts/dispatch.sh plan-verify-r$N`. `WENS_DISPATCH_TIMEOUT=600`.
3. Parse the `out=<path>` file's YAML frontmatter for `status`.
   - `PASS` → exit loop, proceed to Execution Handoff.
   - `ISSUES_FOUND` → main agent edits the plan inline, increment `N`, loop.
   - Malformed frontmatter → synthesize `ISSUES_FOUND` with format-violation issue; re-dispatch with stricter reminder.
   - Non-zero `dispatch.sh` exit → synthesize `ISSUES_FOUND` with stderr tail; retry once; on second failure `AskUserQuestion`.
4. **Round 10 gate:** same as brainstorming — `AskUserQuestion` to continue / pause / accept-as-is. Per-stage counter, not shared with brainstorming.

**Execution Handoff in orchestrated mode:** Do NOT call `AskUserQuestion` for execution mode. Auto-select Subagent-Driven (subagent-driven-development) — the orchestrator already collected the `WENS_MODE=a|b` choice at session start, and subagent-driven-development branches on that internally.
```

- [ ] **Step 2: Verify**

Run: `grep -nE 'Orchestrated Mode: Plan Verification Loop|WENS_ORCHESTRATED' skills/writing-plans/SKILL.md`
Expected: 2+ matches.

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat(writing-plans): add WENS_ORCHESTRATED-gated plan-verify dispatch loop"
```

---

## Task 8: Modify `subagent-driven-development` to add orchestrated per-task branch

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

When `WENS_ORCHESTRATED=1`, per-task flow changes:
- Implementer: mode (b) dispatches via `dispatch-agent`; mode (a) keeps the Task-tool subagent (unchanged).
- Both reviewers (spec compliance, code quality): dispatched via `dispatch-agent` using the orchestrator's templates. The in-skill `spec-reviewer-prompt.md` and `code-quality-reviewer-prompt.md` are **bypassed** in this mode.
- Per-task 10-round gate: reset at the start of each task.

- [ ] **Step 1: Append the orchestrated-mode section**

In `skills/subagent-driven-development/SKILL.md`, locate the `## Integration` heading. Insert the following section **before** it:

```markdown
## Orchestrated Mode (running inside `using-wens-superpowers`)

When the agent is running inside a `using-wens-superpowers` session (marker held by agent context, not by shell env), the per-task loop changes shape. The mode (`WENS_MODE=a` or `WENS_MODE=b`) was selected by the orchestrator at session entry and is likewise carried in agent context.

**Bypass notice.** In orchestrated mode, the in-skill `./spec-reviewer-prompt.md` and `./code-quality-reviewer-prompt.md` templates are **not used**. Reviewers run as `dispatch-agent` calls using:

- `skills/using-wens-superpowers/references/spec-compliance-review-prompt.md`
- `skills/using-wens-superpowers/references/code-review-prompt.md`

Likewise, mode (b) bypasses `./implementer-prompt.md` in favor of `skills/using-wens-superpowers/references/implement-task-prompt.md`.

### Mode (a) — reviewers dispatched, implementer is a Task-tool subagent

Per task:

1. Implementer: invoke Task-tool subagent exactly as in standard mode (`./implementer-prompt.md` *is* used here).
2. After implementer reports COMPLETED, run `git diff --name-only HEAD` from the previous task's commit to collect `files_changed`. Add any files the implementer reported but `git diff` missed.
3. Render `references/spec-compliance-review-prompt.md` (orchestrator skill) with `{{spec_path}}`, `{{task_body}}`, `{{files_changed}}` (joined as a bullet list). Inline substitution by the main agent.
4. Pipe to `skills/using-wens-superpowers/scripts/dispatch.sh spec-compliance-task<i>-r$N`. `WENS_DISPATCH_TIMEOUT=600`.
5. Parse `out=<path>` YAML for `status`. `PASS` → step 7. `ISSUES_FOUND` → re-invoke the same Task-tool implementer subagent with the issue list appended to its prompt, then re-dispatch the spec-compliance reviewer. Increment `N`.
6. Round-10 gate (per-task, per-review-stage). `AskUserQuestion`: continue (reset N), skip-task (mark BLOCKED), abort.
7. Render `references/code-review-prompt.md` with `{{plan_path}}`, `{{task_body}}`, `{{files_changed}}`. Pipe to `dispatch.sh code-review-task<i>-r$N`. `WENS_DISPATCH_TIMEOUT=600`.
8. Same loop semantics as step 5–6 for code review.
9. Mark task complete in TodoWrite, proceed to next task.

### Mode (b) — implementer also dispatched

Per task, step 1 changes:

1. Render `references/implement-task-prompt.md` (orchestrator skill) with `{{spec_path}}`, `{{plan_path}}`, `{{task_body}}`, `{{repo_root}}`. Pipe to `skills/using-wens-superpowers/scripts/dispatch.sh implement-task<i>`. `WENS_DISPATCH_TIMEOUT=1200`.
2. Parse output's YAML for `status: COMPLETED | BLOCKED`. On `BLOCKED`, surface notes to the user via `AskUserQuestion` (continue with edits / retry / abort).
3. Run `git diff --name-only HEAD` (from the previous task's commit) and merge with the implementer's `files_changed` list — the merged list is authoritative for reviewer prompts.
4. Continue with step 3 of mode (a) (spec-compliance review) onward.

Re-dispatching the implementer on review issues in mode (b): re-render `implement-task-prompt.md` with the issue list appended at the end, dispatch again.

### Per-task round counter

Each task starts with `N=1` for both review stages (spec compliance and code quality each have their own counter). The 10-round gate applies independently per stage.

### Risk note for mode (b)

Mode (b) requires the operator's `dispatch-agent` config to have bypass flags enabled (e.g., `--dangerously-skip-permissions`) so the third-party agent can write files. The orchestrator skill (`using-wens-superpowers`) surfaces this risk once at session start; this section restates it for in-context clarity.
```

- [ ] **Step 2: Verify**

Run: `grep -nE 'Orchestrated Mode \(running inside|WENS_MODE' skills/subagent-driven-development/SKILL.md`
Expected: 2+ matches.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(subagent-driven-development): add WENS_ORCHESTRATED per-task dispatch branch"
```

---

## Task 9: Finalize `using-wens-superpowers/SKILL.md` (the orchestrator entry point)

**Files:**
- Modify: `skills/using-wens-superpowers/SKILL.md` (replace the stub from Task 2)

- [ ] **Step 1: Write the full orchestrator SKILL.md**

Replace the contents of `skills/using-wens-superpowers/SKILL.md` with:

```markdown
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

4. **Declare the markers in agent context** by stating, in your own message to the user (and to yourself for future steps): "Running in orchestrated mode: `WENS_ORCHESTRATED=1`, `WENS_MODE=<a|b>`." This is the authoritative marker. Bash tool calls do **not** share shells in Claude Code, so a `export WENS_ORCHESTRATED=1` would not persist; the downstream skills' gate text says "running inside a `using-wens-superpowers` session" and resolves the gate from agent context, not from a shell lookup. For per-call env vars that genuinely need to reach the wrapped binary (e.g., `WENS_DISPATCH_TIMEOUT`), prefix the individual Bash invocation: `WENS_DISPATCH_TIMEOUT=1200 sh skills/using-wens-superpowers/scripts/dispatch.sh implement-task3`.

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
```

- [ ] **Step 2: Verify line count**

Run: `wc -l skills/using-wens-superpowers/SKILL.md`
Expected: ≤ 150 lines (per spec success criterion §11.5).

- [ ] **Step 3: Verify the SKILL.md does not duplicate content from the three modified skills**

Run: `grep -cE 'checklist|spec self-review|plan verification|per task|round 10 gate' skills/using-wens-superpowers/SKILL.md`
Expected: low (each occurs at most once in summary form; the loop body lives inside the downstream skills).

- [ ] **Step 4: Commit**

```bash
git add skills/using-wens-superpowers/SKILL.md
git commit -m "feat(using-wens-superpowers): finalize orchestrator SKILL.md"
```

---

## Task 10: End-to-end smoke test (manual, scripted, mock dispatch-agent)

**Files:**
- Create: `tests/using-wens-superpowers/smoke-end-to-end.sh`

Validates: WENS_ORCHESTRATED gating works correctly (downstream skills' branches are not executed when the marker is unset), and the `dispatch.sh` artifact paths flow through as expected.

- [ ] **Step 1: Write the smoke test**

Write `tests/using-wens-superpowers/smoke-end-to-end.sh`:

```sh
#!/bin/sh
# Smoke test: dispatch.sh with a mock dispatch-agent, simulating the spec-review
# round-1 round-trip the main agent would perform.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$REPO_ROOT/skills/using-wens-superpowers/scripts/dispatch.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR" || exit 1
git init -q .
mkdir -p bin
cat > bin/dispatch-agent <<'EOF'
#!/bin/sh
# Mock that echoes back its prompt file content prefixed with PASS YAML.
PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f) shift; PROMPT="$1"; shift ;;
    *) shift ;;
  esac
done
printf -- '---\nstatus: PASS\nissues: []\n---\n\nProcessed: %s\n' "$PROMPT"
EOF
chmod +x bin/dispatch-agent

PATH="$WORKDIR/bin:$PATH" WENS_DISPATCH_TIMEOUT=30 sh "$DISPATCH" spec-review-r1 \
  > /dev/null 2> stderr.log <<EOF_PROMPT
# Spec Review — Round 1
Review the spec at /tmp/spec.md.
EOF_PROMPT

rc=$?
[ "$rc" = "0" ] || { echo "FAIL: exit code $rc"; exit 1; }

prompt_path=$(grep -o 'prompt=[^ ]*' stderr.log | head -1 | cut -d= -f2)
out_path=$(grep -o 'out=[^ ]*' stderr.log | head -1 | cut -d= -f2)
[ -f "$prompt_path" ] || { echo "FAIL: prompt file missing"; exit 1; }
[ -f "$out_path" ] || { echo "FAIL: out file missing"; exit 1; }
grep -q "Spec Review — Round 1" "$prompt_path" || { echo "FAIL: prompt content wrong"; exit 1; }
grep -q "status: PASS" "$out_path" || { echo "FAIL: out content wrong"; exit 1; }
case "$prompt_path" in
  */docs/tmp/*) ;;
  *) echo "FAIL: prompt not under docs/tmp/: $prompt_path"; exit 1 ;;
esac

echo "PASS: end-to-end smoke"
```

```bash
chmod +x tests/using-wens-superpowers/smoke-end-to-end.sh
```

- [ ] **Step 2: Run the smoke test**

Run: `tests/using-wens-superpowers/smoke-end-to-end.sh`
Expected: `PASS: end-to-end smoke`

- [ ] **Step 3: Re-run the dispatch tests to confirm no regression**

Run: `tests/using-wens-superpowers/run-dispatch-tests.sh`
Expected: `Results: 5 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git add tests/using-wens-superpowers/smoke-end-to-end.sh
git commit -m "test(using-wens-superpowers): add end-to-end smoke test"
```

---

## Task 11: CHANGELOG entry + README pointer

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md` (only if a skills list exists; otherwise skip)

- [ ] **Step 1: Inspect CHANGELOG and README structure**

Run: `head -40 CHANGELOG.md && echo '---' && grep -nE 'skills|using-superpowers' README.md | head -20`

- [ ] **Step 2: Add Unreleased entry to CHANGELOG.md**

Locate (or create) the `## Unreleased` section at the top of `CHANGELOG.md`. Append under it:

```markdown
- Added `using-wens-superpowers` skill: orchestrates brainstorm → plan → implement flow with `dispatch-agent`-driven external review at each stage, gated by `WENS_ORCHESTRATED=1`.
- Modified `brainstorming`, `writing-plans`, `subagent-driven-development` to add `WENS_ORCHESTRATED`-gated dispatch loops. Standalone (unset) behavior unchanged.
```

If `## Unreleased` does not exist, add it as a new section directly under the file's title, before the most recent dated release.

- [ ] **Step 3: README pointer (if applicable)**

If `README.md` lists skills (look for "using-superpowers" or a "skills/" section), add a single line pointing to the new skill, mirroring the style of adjacent entries. If no such list exists, skip.

- [ ] **Step 4: Verify**

Run: `grep -n 'using-wens-superpowers' CHANGELOG.md`
Expected: at least one match.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: changelog entry for using-wens-superpowers skill"
```

---

## Task 12: Final review pass + push

**Files:** (no file changes; verification only)

- [ ] **Step 1: Re-run all tests**

Run: `tests/using-wens-superpowers/run-dispatch-tests.sh && tests/using-wens-superpowers/smoke-end-to-end.sh`
Expected: both green.

- [ ] **Step 2: Confirm no untracked artifacts in `docs/tmp/`**

Run: `git status --short docs/ 2>&1`
Expected: empty (the test scripts use temp dirs, not the repo's `docs/tmp/`).

- [ ] **Step 3: Confirm upstream sync**

Run: `git fetch upstream main && git log --oneline upstream/main..HEAD | head -20`
Expected: lists the commits from this plan. If `upstream/main..HEAD` shows unexpected drift, investigate.

- [ ] **Step 4: Verify success criteria from spec §11**

Run:
```bash
wc -l skills/using-wens-superpowers/SKILL.md skills/using-wens-superpowers/scripts/dispatch.sh
grep -E '^docs/tmp/' .gitignore
```

Expected:
- `SKILL.md` ≤ 150 lines
- `dispatch.sh` ≤ 45 lines
- `.gitignore` has `docs/tmp/`

- [ ] **Step 5: Push to origin (fork)**

Run: `git push origin main`
Expected: clean push, no force.

---

## Out of scope (explicitly)

- Revising the spec file in the `myskills` repo. The plan reflects the locked decisions; spec revisions are tracked separately by the user.
- Adding `using-wens-superpowers` as a triggerable bootstrap from `/using-superpowers`. The two skills coexist; user must explicitly type `/using-wens-superpowers`.
- Pushing this fork upstream to `obra/superpowers`. This is a fork-local workflow.
- Automating cleanup of `docs/tmp/`. User cleans manually.
- A `.skill` ZIP bundle for distribution.

## Self-review notes

**Spec coverage:** every section of the spec maps to a task — §5 stages 1–7 → tasks 6, 7, 8, 9; §6 dispatch contract → tasks 3, 4; §7 prompt templates → task 5; §8 file layout → tasks 2, 4, 5, 9; §9 gitignore → tasks 1, 9; §10 risks (mode b warning) → task 9 + task 8; §11 success criteria → task 12 step 4. Round-1 review issues' resolutions are tabulated in "Spec Reference" at the top.

**Placeholder scan:** every step lists exact paths, exact commands, and complete code. No "implement appropriately" or "similar to task N" without repeated content.

**Identifier consistency:** `WENS_ORCHESTRATED` (not `WENS_ORCH` or `WENS_ENABLED`) used everywhere. `WENS_MODE=a|b` (not `MODE_A`). `WENS_DISPATCH_TIMEOUT` (not `DISPATCH_TIMEOUT`). `dispatch.sh` (not `dispatch-wrapper.sh`). Slug patterns (`spec-review-r<N>`, `plan-verify-r<N>`, `implement-task<i>`, `spec-compliance-task<i>-r<N>`, `code-review-task<i>-r<N>`) consistent between tasks 3, 6, 7, 8, 9 and the spec §6.
