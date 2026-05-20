# wens-superpowers orchestrator — round-2 optimization

**Date:** 2026-05-20
**Scope target:** the `using-wens-superpowers` orchestrator skill and its three
auto-chained downstream skills (`brainstorming`, `writing-plans`,
`subagent-driven-development`), plus the dispatch wrapper script and the five
reviewer prompt templates.

## 1. Motivation

Two AI-generated post-session reflections — one from the main agent and one
from the dispatch-side agent — identified concrete friction in the
orchestrated review loop after running a real 12–14 task feature through it
end-to-end. Both reports converged on the same high-leverage targets:

- dispatch reliability (empty output with exit code 0, no stderr signal,
  ~5% silent failure rate)
- reviewer scope creep across task boundaries
- unstable YAML response contract (undeclared severities, fenced
  frontmatter, prose responses)
- R2+ review rounds being exhaustive re-reads rather than verify-only,
  producing new findings instead of confirming R1 fixes
- main-agent failure to use `TaskCreate` for progress tracking
- excessive token cost from inlining whole task bodies into prompts
- `dispatch-agent` binary needs to be replaced with the user's own
  `agd` CLI

This spec implements the user's four explicit asks plus the four high-ROI
fixes both reports converged on, in a single PR.

## 2. In scope

1. **Hard switch** from `dispatch-agent` to `agd`
   (https://github.com/superyngo/agd) — no transitional compatibility layer.
2. **Timeout tiers**: 4-tier defaults (spec-review 15 min / plan-verify
   20 min / implement 30 min / reviewer 15 min); `WENS_DISPATCH_TIMEOUT`
   env var still overrides.
3. **`docs/tmp/` vs `/tmp/` policy**: status quo behavior, documented.
4. **A1 — empty-output retry**: `dispatch.sh` internally retries once on
   empty or no-frontmatter output.
5. **A2 — reviewer scope guard**: text rule embedded in every reviewer
   template; plan task header list passed as out-of-scope reference to the
   three plan-aware reviewers.
6. **A3 — YAML stability**: closed severity vocabulary
   (`blocker | major | minor`); main-agent tolerant parsing with no
   dispatch-side retry on format violation.
7. **A4 — R2+ verify-only with blocker exception**: rounds ≥ 2 must
   verify R1 issues only; new findings allowed only at severity `blocker`.
   R1 issues passed inline.
8. **TaskCreate mandatory** in `subagent-driven-development` orchestrated
   branch; `TodoWrite` legacy name removed.
9. **Mode (b) precondition probe** for agd bypass flag; cost-estimate gate
   before first dispatch.
10. **Git safety**: `git add <specific-files>` only, no `-am`, in
    orchestrated mode.
11. **Evaluation chapter** (Section 11): whether to dispatch spec/plan
    writing itself — analysis only, no code changes.

## 3. Architecture overview

Single PR. Files touched:

```
skills/using-wens-superpowers/
├── SKILL.md
│   prereq agd; entry checklist + bypass probe; /tmp policy section;
│   git -am safety note; downstream-table tier numbers
├── scripts/
│   └── dispatch.sh
│       agd binary; 4-tier timeout default; empty-output retry; stderr
│       lines for tier + retry
└── references/
    ├── spec-review-prompt.md            — scope guard, severity, R2+
    ├── plan-verify-prompt.md            — + plan task headers slot
    ├── implement-task-prompt.md         — scope guard only
    ├── spec-compliance-review-prompt.md — + plan task headers slot
    └── code-review-prompt.md            — + plan task headers slot

skills/brainstorming/SKILL.md            — orchestrated section: new tier,
                                            new retry, R2+ rules, tolerant
                                            parse, Behavior reference block
skills/writing-plans/SKILL.md            — same + plan_task_headers slot
skills/subagent-driven-development/SKILL.md
    TaskCreate mandate; cost estimate gate; reviewer dispatch passes
    plan task headers; R1 inline carry-over; tolerant parse rules;
    git add safety
```

Untouched: standard (non-orchestrated) branches of all three downstream
skills; other skills; harness wrappers.

## 4. dispatch.sh

### 4.1 Interface

- argv[1]: slug (e.g. `spec-review-r1`, `implement-task3`,
  `code-review-task5`)
- stdin: rendered prompt (written by `dispatch.sh` to
  `docs/tmp/<base>.md`, then passed to `agd` via `-f`)
- stderr: `prompt=<path>` and `out=<path>` lines (existing main-agent
  parser keeps working), plus new `timeout=... tier=...` and optional
  `retry=1 reason=...`
- stdout from agd: redirected to `<base>.out.md` (existing convention;
  combined with stderr via `2>>"$OUT"`)
- exit code: mirrors agd's; 127 if `agd` not on `PATH`; 2 on malformed
  argv

**Invocation pattern** (matches the existing `dispatch-agent dispatch -f
<prompt> --timeout <s>` interface): `agd dispatch -f "$PROMPT"
--timeout "$TIMEOUT"`. See §10.4 OQ for compatibility verification at
plan stage — if `agd`'s flag names differ, `dispatch.sh` adapts; no
spec change needed.

### 4.2 New stderr lines

```
timeout=900 tier=spec-review     # every invocation
retry=1 reason=empty_output      # only when retry triggered
retry=1 reason=no_frontmatter    # alternate reason
```

### 4.3 Timeout tier table

| slug prefix                                   | tier         | default (s) |
|-----------------------------------------------|--------------|-------------|
| `spec-review*`                                | spec-review  | 900         |
| `plan-verify*`                                | plan-verify  | 1200        |
| `implement-task*`                             | implement    | 1800        |
| `spec-compliance-review*`, `code-review*`     | review       | 900         |
| other                                         | review       | 900         |

Override priority: `WENS_DISPATCH_TIMEOUT` env var → tier default.

### 4.4 Empty-output retry

Trigger (OR):
1. `out.md` is empty (POSIX `! -s`).
2. `out.md` does not contain `^---` or `^status:` anywhere (no YAML
   frontmatter).

Behavior: identical prompt re-sent once. stderr emits
`retry=1 reason=<empty_output|no_frontmatter>`. Second failure is not
retried — output is returned as-is for the main agent's tolerant parser
(§7.5). Exit code remains 0 unless `agd` itself returned non-zero on the
second attempt.

### 4.5 Mode (b) bypass-flag probe

Performed **once** by `using-wens-superpowers/SKILL.md` entry checklist
after mode selection — not by `dispatch.sh` on every call, since 36+
dispatches per session would otherwise each spawn `agd --help`.

```sh
agd --help 2>&1 | grep -qE -- '--dangerously-skip-permissions|--bypass'
```

If probe fails and user has selected mode (b), `AskUserQuestion`:
proceed at own risk / abort / switch to mode (a).

### 4.6 Reference skeleton

Mirrors the existing dispatch.sh structure (REPO_ROOT, sed-based slug
sanitizer, agd invoked with `dispatch -f` and `--timeout`); adds tier
table and post-call empty-output retry.

```sh
#!/bin/sh
# dispatch.sh — wraps `agd dispatch -f` for using-wens-superpowers.
# Reads prompt from stdin; writes prompt + .out.md to
# docs/tmp/<ts>_<pid>-<slug>.{md,out.md}. Emits prompt=, out=,
# timeout=, tier= on stderr (+ retry= on retry). Exit code mirrors agd
# (127 if not on PATH, 2 if argv malformed). Override per-call via
# WENS_DISPATCH_TIMEOUT.
set -u

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "dispatch.sh: missing <phase-slug> argument" >&2
  echo "usage: cat prompt.md | dispatch.sh <phase-slug>" >&2
  exit 2
fi

if ! command -v agd >/dev/null 2>&1; then
  echo "dispatch.sh: 'agd' not found on PATH." >&2
  echo "  Install it (https://github.com/superyngo/agd)" >&2
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

## 5. Reviewer prompt templates

Five templates share four common blocks, embedded per-template (no shared
partial — Approach 1).

### 5.1 Block A — Scope Guard (all 5 templates)

Inserted after the "You are reviewing" preamble, before the output contract.

```markdown
## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in
  plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.
```

`{{stage}}` resolved by the main agent from the slug
(`spec` / `plan` / `task N`).

### 5.2 Block B — Plan Task Header List (3 templates)

`plan-verify-prompt.md`, `spec-compliance-review-prompt.md`,
`code-review-prompt.md` only. Inserted after Scope Guard.

```markdown
## Other tasks in plan (for scope reference, NOT for review)

{{plan_task_headers}}

Use this list to recognize findings that belong to a different task than
the one being reviewed. Those findings are out of scope.
```

`{{plan_task_headers}}` populated by main agent from
`rg '^## Task ' <plan-file>` output.

`spec-review-prompt.md` (no plan yet) and `implement-task-prompt.md`
(this is the implementer, not a reviewer) skip Block B.

### 5.3 Block C — Severity Vocabulary (4 reviewer templates)

Excludes `implement-task-prompt.md`. Inserted into the output contract
section.

```markdown
## Severity (CLOSED VOCABULARY)

Each issue MUST use exactly one of:
- `blocker` — would break correctness, security, or the acceptance gates.
- `major`   — substantive design or correctness problem, not blocking.
- `minor`   — style, naming, doc nit.

Do NOT invent other severities (no `medium`, `low`, `pass-note`, `nit`,
etc.).
```

### 5.4 Block D — Round Discipline (4 reviewer templates)

Same set as Block C. Inserted after severity block.

```markdown
## Round Discipline

If `{{round}} == 1`:
  Perform a focused review. Spot-check 3-5 load-bearing claims. Before
  emitting any finding, grep to verify the file/symbol/line actually
  exists.

If `{{round}} >= 2`:
  You are in **verify-only mode**. The R1 issues are listed below under
  "R1 issues to verify". Confirm each is resolved
  (`status: resolved | unresolved | partially-resolved`).
  You MAY add NEW findings ONLY at severity `blocker`. Do NOT add `major`
  or `minor` findings — those wait for the next iteration.

  ### R1 issues to verify
  {{r1_issues_inline}}
```

For round 1 dispatches, `{{r1_issues_inline}}` renders to the empty string;
the conditional block is kept in the template so the LLM reads the rule.

### 5.5 Per-template block matrix

| Template                         | A Scope | B Plan list | C Severity | D Round |
|----------------------------------|:-------:|:-----------:|:----------:|:-------:|
| spec-review-prompt.md            | ✓       | ✗           | ✓          | ✓       |
| plan-verify-prompt.md            | ✓       | ✓           | ✓          | ✓       |
| implement-task-prompt.md         | ✓       | ✗           | ✗          | ✗       |
| spec-compliance-review-prompt.md | ✓       | ✓           | ✓          | ✓       |
| code-review-prompt.md            | ✓       | ✓           | ✓          | ✓       |

### 5.6 New placeholders

| Placeholder              | Filled by  | Source                                       |
|--------------------------|------------|----------------------------------------------|
| `{{stage}}`              | main agent | slug                                         |
| `{{plan_task_headers}}`  | main agent | `rg '^## Task ' <plan-file>`                 |
| `{{round}}`              | main agent | existing N counter                           |
| `{{r1_issues_inline}}`   | main agent | R1 out.md issues section; empty for R1      |

## 6. `subagent-driven-development` orchestrated section

The heaviest change. Six sub-changes inside its existing orchestrated
branch.

### 6.1 TaskCreate mandate

Inserted at the top of the orchestrated section, before the first
dispatch:

```markdown
## Orchestrated Mode — Task Tracking (MANDATORY)

Before dispatching the first task, you MUST call `TaskCreate` once per
plan task, using the plan's `## Task N:` header text as the task subject.
This is not optional — the user cannot see your progress otherwise, and
a context compaction loses your in-memory state.

Use exactly this sequence per task:

1. `TaskUpdate <id> status=in_progress` before dispatching the
   implementer (mode b) or before starting local implementation (mode a).
2. After spec-compliance review PASS: keep status `in_progress`.
3. After code review PASS: `TaskUpdate <id> status=completed`.
4. If either review returns ISSUES_FOUND: keep `in_progress` and
   iterate. Do NOT create sub-tasks per fix iteration — that explodes
   the list.

The previous wording referenced `TodoWrite`. That is the legacy name;
use whatever the current harness exposes as `TaskCreate` /
`TaskUpdate` / `TaskList`.
```

### 6.2 Cost estimate gate (mode b only)

```markdown
## Mode (b) Cost Estimate

Before the first dispatch in mode (b), surface to the user:

> 「將透過 agd dispatch N 個 tasks，每個 task 含 1 implementer + 2
>  reviewers = 3N 次 dispatch。預估 3N 次 agd 呼叫，不含 review 迭代。
>  確認繼續嗎？」

Use AskUserQuestion with options: 繼續 / 中止 / 改用 mode (a).
N is taken from the TaskList count.
```

Mode (a) does not perform this gate.

### 6.3 Reviewer dispatch — passing plan task headers

Each reviewer dispatch renders its prompt with `{{plan_task_headers}}`
populated by `rg '^## Task ' <plan-file>`. If the plan path is not in the
default `docs/superpowers/specs/` location, fall back to TaskList task
subjects.

### 6.4 R1 → R2+ inline carry-over

```markdown
For each reviewer dispatch beyond round 1:
- Read previous out.md
- Extract the YAML `issues:` list
- Inline-substitute into `{{r1_issues_inline}}` of the next prompt
- Increment {{round}}
```

### 6.5 Tolerant parsing of reviewer output

```markdown
## Tolerant Parsing of Reviewer Output

When reading reviewer out.md, apply in order:

1. If the body is wrapped in ```yaml ... ``` fences, strip them.
2. Parse the leading YAML frontmatter (between `---` lines).
3. If frontmatter is absent or unparseable: treat as
   `status: ISSUES_FOUND` with a single synthetic issue noting the
   format violation. Do NOT retry dispatch — proceed to fix-iteration
   with the body as freeform text.
4. For each issue's `severity`:
   - If in {blocker, major, minor}: accept as-is.
   - Otherwise (e.g. medium, low, nit, pass-note): coerce to `minor`
     and note the coercion to the user once per session.
```

### 6.6 Git safety

```markdown
## Git Operations in Orchestrated Mode

The dispatched implementer (mode b) decides its own commit boundary.
Any additional commits the main agent creates (rare — typically only for
finalization docs) MUST use:

    git add <specific-file>...
    git commit -m "..."

Do NOT use `git commit -am` or `git add -A`. The orchestrated session
has generated artifacts in `docs/tmp/` (gitignored) plus working-tree
changes from recently dispatched tasks — `-am` will sweep unrelated
edits into the wrong commit.
```

### 6.7 Existing wording updated

- Timeout reference:
  - old: ``set `WENS_DISPATCH_TIMEOUT=1200` ``
  - new: "tier defaults apply (see `dispatch.sh`); set
    `WENS_DISPATCH_TIMEOUT` only to override"
- Empty-output handling:
  - old: "on dispatch failure, retry once"
  - new: "`dispatch.sh` retries empty / no-frontmatter output
    internally; main agent handles only non-zero exit and post-retry
    failures"

## 7. `brainstorming` and `writing-plans` orchestrated sections

Minimal text updates referencing new defaults and behaviors. Both skills
get four changes; `writing-plans` gets one additional.

### 7.1 Timeout reference

- `brainstorming`: tier default 900 s (15 min) for spec-review.
- `writing-plans`: tier default 1200 s (20 min) for plan-verify.
- Both: env override remains.

### 7.2 Empty-output handling

`dispatch.sh` retries internally; main agent only retries on non-zero
exit or post-retry format violation. On second failure, surface via
`AskUserQuestion`.

### 7.3 R2+ rules

```markdown
From round 2 onward, the template enforces verify-only mode: new
findings allowed only at severity blocker. R1 issues are passed inline
via {{r1_issues_inline}} — main agent extracts the issues section from
the previous out.md and substitutes before dispatch.
```

### 7.4 Tolerant parsing

```markdown
Parse out.md leniently: strip ```yaml fences if present; treat
non-{blocker,major,minor} severities as minor; missing frontmatter →
ISSUES_FOUND with synthetic format-violation issue.
```

### 7.5 `writing-plans` only — plan task headers

```markdown
When rendering plan-verify-prompt.md, populate {{plan_task_headers}}
with the output of `rg '^## Task ' <plan-file>`.
```

### 7.6 Behavior reference (both skills, near orchestrated entry)

```markdown
**Behavior reference.** The dispatch wrapper (`scripts/dispatch.sh`)
handles timeout tiers, empty-output retry, and slug sanitization on its
own. The reviewer prompt templates handle scope guard, severity
vocabulary, and R2+ verify-only on their own. Main-agent responsibilities
are limited to:

1. Rendering placeholders ({{spec_path}}, {{round}}, {{r1_issues_inline}},
   {{plan_task_headers}}).
2. Parsing reviewer out.md (tolerant rules above).
3. Editing the spec/plan file inline to apply confirmed findings.
4. Deciding loop exit (PASS) vs continue (ISSUES_FOUND).
5. Surfacing the round-10 gate via AskUserQuestion.
```

## 8. `using-wens-superpowers/SKILL.md`

### 8.1 Prereq section

```diff
- - `dispatch-agent` CLI on `PATH`. The wrapper script will exit 127 ...
- - For mode (b): your `dispatch-agent` config must enable bypass flags ...
+ - `agd` CLI on `PATH` (https://github.com/superyngo/agd). The wrapper
+   script will exit 127 if missing.
+ - For mode (b): `agd --help` must show a
+   `--dangerously-skip-permissions` (or equivalent bypass) flag. The
+   entry checklist probes this.
```

### 8.2 Entry checklist (5 → 7 steps)

1. Ensure `.gitignore` ignores `docs/tmp/` (unchanged).
2. Confirm `agd` installed (`command -v agd`); 127 + repo URL on miss.
3. **(new) Bypass-flag probe** (one-shot):
   ```sh
   agd --help 2>&1 | grep -qE -- \
     '--dangerously-skip-permissions|--bypass' \
       && echo bypass-ok || echo bypass-missing
   ```
4. Ask for mode via `AskUserQuestion` (wording adjusted to mention agd).
5. **(new) Mode (b) precondition gate**: if probe returned
   `bypass-missing` and mode (b) was selected, AskUserQuestion: continue
   at own risk / abort / switch to mode (a).
6. **(new) Cost estimate preview**: print once, no question:
   > 「Mode (b) 將透過 agd 跑 implementer + 2 reviewers。實際 dispatch
   >  數 = 3 × (plan task 數)，將於 subagent-driven-development 開跑前
   >  再次確認。」
   The actual cost gate is enforced in `subagent-driven-development`
   (§6.2), since plan task count is unknown at brainstorming entry.
7. Declare markers (`WENS_ORCHESTRATED=1`, `WENS_MODE=<a|b>`) in
   conversation context. Invoke `Skill(brainstorming)`.

### 8.3 New section — `/tmp/` vs `docs/tmp/` policy

Placed after the existing "Artifacts" section.

```markdown
## `/tmp/` vs `docs/tmp/` — When to use which

`docs/tmp/` — repo-local, gitignored, persists across the session:
- All `dispatch.sh` artifacts (`*.md` prompt, `*.out.md` agd response).
- Anything that may need to be audited or quoted in fix iterations.
- Anything a future reviewer round may need to reread.

`/tmp/` — system tmp, ephemeral, cross-repo:
- Main agent ad-hoc scratch (e.g. `/tmp/task5-body.md` for extracting a
  task body from the plan before dispatch).
- One-shot intermediate files with no audit value.
- Pipes between commands.

Rule of thumb: if `dispatch.sh` wrote it, it goes in `docs/tmp/`. If the
main agent wrote it directly via Bash, it goes in `/tmp/`. Clean either
at session end if desired (`rm -rf docs/tmp` for the repo side).
```

### 8.4 "What happens downstream" table — updated rows

```
| Spec      | brainstorming                 | After spec self-review,
  loops `agd` spec-review (tier 15 min, R2+ verify-only with R1 issues
  inline) until `status: PASS` (10-round user gate).
| Plan      | writing-plans                 | After self-review, loops
  `agd` plan-verify (tier 20 min) until PASS. Auto-selects
  subagent-driven-development for execution.
| Implement | subagent-driven-development   | Per task: mode (b)
  dispatches implementer (tier 30 min); both modes dispatch
  spec-compliance + code-review reviewers (tier 15 min). Cost estimate
  gate before first dispatch in mode (b). TaskCreate is mandatory for
  progress tracking.
```

### 8.5 Finalization section — git safety addition

```markdown
4. When the main agent does need to commit (e.g. changelog updates),
   use `git add <specific-files>` only. Never `git commit -am` or
   `git add -A` in orchestrated mode — see
   subagent-driven-development for rationale.
```

### 8.6 Prompt templates section — placeholder note

Append:

> All templates use `{{placeholder}}` substitution rendered inline by
> the main agent. Placeholders now include `{{stage}}`,
> `{{plan_task_headers}}`, `{{round}}`, and `{{r1_issues_inline}}` in
> addition to the existing per-template ones. See
> `skills/subagent-driven-development/SKILL.md` for the rendering
> contract.

## 9. Testing & acceptance gates

### 9.1 Static grep gates (must all pass)

```sh
# A. dispatch-agent legacy name removed
test "$(rg -n 'dispatch-agent' skills/ | wc -l)" -eq 0

# B. agd present in orchestrator
rg -q '`agd`' skills/using-wens-superpowers/SKILL.md

# C. dispatch.sh syntax + tokens
bash -n skills/using-wens-superpowers/scripts/dispatch.sh
rg -q 'tier=' skills/using-wens-superpowers/scripts/dispatch.sh
rg -q 'retry=1 reason=' skills/using-wens-superpowers/scripts/dispatch.sh

# D. Reviewer template blocks
test "$(rg -l 'Scope Guard' skills/using-wens-superpowers/references/ | wc -l)" -eq 5
test "$(rg -l 'CLOSED VOCABULARY' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l 'verify-only mode' skills/using-wens-superpowers/references/ | wc -l)" -eq 4
test "$(rg -l 'plan_task_headers' skills/using-wens-superpowers/references/ | wc -l)" -eq 3

# E. subagent-driven-development orchestrated section
rg -q 'TaskCreate' skills/subagent-driven-development/SKILL.md
test "$(rg 'TodoWrite' skills/subagent-driven-development/SKILL.md | wc -l)" -eq 0
rg -q 'git add <specific' skills/subagent-driven-development/SKILL.md
rg -q 'tolerant|coerce' skills/subagent-driven-development/SKILL.md
rg -q 'AskUserQuestion' skills/subagent-driven-development/SKILL.md

# F. brainstorming & writing-plans references updated
test "$(rg -l 'Behavior reference' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md | wc -l)" -eq 2
test "$(rg -l 'verify-only mode' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md | wc -l)" -eq 2
rg -q 'plan_task_headers' skills/writing-plans/SKILL.md

# G. /tmp policy section present
rg -q 'ephemeral|system tmp' skills/using-wens-superpowers/SKILL.md
```

### 9.2 dispatch.sh smoke (fake-agd)

```sh
cat > /tmp/fake-agd.sh <<'EOF'
#!/usr/bin/env sh
# Mimics `agd dispatch -f <prompt> --timeout <s>` interface.
# First call: exit 0 with no output (triggers retry).
# Second call: emit canonical PASS frontmatter.
state_file=/tmp/fake-agd-state
if [ -f "$state_file" ]; then
  printf -- '---\nstatus: PASS\n---\n'
else
  touch "$state_file"
  :  # exit 0 with no output
fi
EOF
chmod +x /tmp/fake-agd.sh
rm -f /tmp/fake-agd-state
mkdir -p /tmp/fake-agd-bin
ln -sf /tmp/fake-agd.sh /tmp/fake-agd-bin/agd
PATH="/tmp/fake-agd-bin:$PATH"

echo "test" | sh skills/using-wens-superpowers/scripts/dispatch.sh \
  spec-review-r1 2> /tmp/stderr.log
rg -q 'retry=1 reason=empty_output' /tmp/stderr.log
rg -q 'timeout=900 tier=spec-review' /tmp/stderr.log

echo "test" | sh skills/using-wens-superpowers/scripts/dispatch.sh \
  implement-task5 2> /tmp/stderr2.log
rg -q 'timeout=1800 tier=implement' /tmp/stderr2.log
```

### 9.3 End-to-end smoke (manual reproducer)

1. Fresh session, invoke `/using-wens-superpowers`.
2. Confirm entry checklist:
   - `agd` prereq message visible.
   - Bypass probe result visible (stderr or chat).
   - Mode question appears.
3. Select mode (b), give a simple request (e.g., "append a timestamp to
   README").
4. Expected:
   - brainstorming → spec-review runs ≥ 1 round of `agd` dispatch;
     stderr shows `timeout=900 tier=spec-review`.
   - writing-plans completes; cost estimate `3 × N tasks` printed.
   - subagent-driven-development opens with `TaskList` showing N entries.
   - Each task transitions `in_progress` → `completed`.
   - Any reviewer out.md with non-canonical severity prints
     "coerced severity X → minor" once.
5. `ls docs/tmp/` contains dispatch artifacts; `/tmp/` may contain
   main-agent scratch.
6. `git log` shows commits from the implementer only — no `-am`
   sweep-commits.

### 9.4 PR acceptance checklist (spec self-claim)

- [ ] §9.1 grep gates all pass.
- [ ] §9.2 dispatch.sh smoke passes.
- [ ] §9.3 end-to-end smoke run at least once (attach `docs/tmp/`
      excerpt or stderr snippet as evidence).
- [ ] `CHANGELOG.md` Unreleased entry appended.
- [ ] §11 Evaluation chapter present and complete.

## 10. Out of scope, risks, rollback

### 10.1 Explicitly out of scope

| Item                                                 | Source             | Why not |
|------------------------------------------------------|--------------------|---------|
| `wens-extract-task <N>` helper                       | main-agent report  | `/tmp/` documented (§8.3); helper is an extra abstraction |
| Token cost estimator with prices                     | main-agent report  | §6.2 simplified to dispatch count; pricing API integration YAGNI |
| Task-type aware reviewer strictness                  | main-agent report  | No structured task-type metadata in plan; §5.4 "spot-check 3-5" already mitigates |
| Parallel spec-review and code-review                 | main-agent report  | Violates current sequential design; main-flow refactor out of scope |
| Implementer + self-review combined                   | main-agent report  | Loses fresh-eyes value, contradicts mode (b) design |
| Reviewer fed sub-sections of spec/plan               | both reports       | Needs markdown heading extractor; high ROI but separate PR |
| Task body via reference (not inline) in prompts      | dispatch-agent     | Same — separate PR |
| Helper "grep status only, print body on ISSUES_FOUND" | main-agent report | §6.5 tolerant parser supersedes |
| dispatch.sh JSON stderr                              | dispatch-agent     | `key=value` is already parseable |
| `--strict-output` / `--severity-vocabulary` flags    | dispatch-agent     | Defined in templates (§5); parser handles violations (§6.5) |
| Round counter metadata, `--round N` flag             | dispatch-agent     | TaskCreate metadata + slug naming suffice |
| Cancel / resume support                              | main-agent report  | Violates one-shot dispatch semantics |
| `dispatch-agent` backward compatibility              | §2 decision        | Hard switch |
| Dispatched spec/plan writing                         | §11 evaluation     | Conclusion: not now |
| Reviewer self-grep verification (separate mechanism) | dispatch-agent     | Folded into §5.4 R1 round discipline text |
| Auto-cleanup of `docs/tmp/` at session end           | dispatch-agent     | Manual per §8.3; auto-cleanup risk > value |

### 10.2 Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `agd` CLI differs from `dispatch-agent` (stdin/stdout/exit) | Medium | High | §9.2 fake-agd smoke; §9.3 e2e at least once with real agd |
| `agd --help` doesn't contain `--dangerously-skip-permissions` literal | Medium | Medium | Probe uses `-E ...|--bypass`; user gate (§8.2.5) catches misses |
| 4-tier timeouts too tight for some agd back-ends | Low | Medium | env override documented in CHANGELOG |
| Reviewer still violates scope guard (LLM drift) | Medium | Low | Scope guard + plan task list both present; main agent judgment final |
| R2+ verify-only misses a real new blocker | Low | Medium | §5.4 D explicitly allows new blocker findings |
| TaskCreate API renamed by harness | Low | Low | SKILL.md says "whatever current harness exposes" |
| Empty-output false positive (legit short PASS) | Very low | Low | Empty-check uses `! -s` (zero bytes only); any frontmatter-bearing response satisfies the secondary `grep` clause |

### 10.3 Rollback

Single PR; full revert via `git revert <merge-commit>`. Internal commits
(per `subagent-driven-development` task split) are independently
revertable. No backup of old `dispatch-agent` binary in repo.

### 10.4 Open questions (resolve during plan/implement)

1. Exact `agd --help` flag name for bypass — adjust probe regex.
2. Confirm `agd` accepts the existing dispatch-agent invocation
   pattern `agd dispatch -f <file> --timeout <s>`. If flag names
   differ, adapt `dispatch.sh` at implement time without spec change.
3. Existing files in `docs/tmp/` not cleaned by this PR — user decides.

## 11. Evaluation: dispatched spec/plan writing

> [!NOTE]
> This section is an evaluation, not a deliverable. No code changes
> correspond to it.

### 11.1 The idea

Move spec and plan **writing** itself into `agd` dispatches. Main agent
roles narrow to: user dialogue, decision-point confirmation,
documenting decisions into an `input.md`, judging whether agd-produced
spec/plan needs another round.

### 11.2 Token estimate (±30%)

Baseline: the reflection session that produced this spec.

| Stage                          | Current main-agent tokens | Idea (main agent only) | Delta |
|--------------------------------|---------------------------|------------------------|-------|
| Brainstorming Q&A              | ~15k                      | ~15k                   | 0 |
| Spec writing                   | ~25k                      | ~3k                    | −22k |
| Spec review loop (4 rounds)    | ~40k                      | ~10k                   | −30k |
| Plan writing                   | ~20k                      | ~3k                    | −17k |
| Plan verify (2 rounds)         | ~20k                      | ~6k                    | −14k |
| Implement (12 tasks × 3 disp.) | ~60k                      | ~60k                   | 0 |
| **Total main-agent tokens**    | **~180k**                 | **~97k**               | **~−46%** |

Dispatch-side overhead: +2 dispatches (spec-writer, plan-writer);
+<10% over current dispatch budget.

### 11.3 Trade-offs

**For**

1. Main-agent context is the scarcer resource at large project size.
2. ~46% token saving.
3. Cleaner role separation — main agent becomes purely decision-keeper.

**Against**

1. **Dialogue fidelity**: spec is the written form of user consensus.
   Outsourcing the write step means a round-trip when the user spots
   "this isn't what I meant" — increases friction rather than reducing
   it.
2. **Decision-point transfer**: passing all dialogue context to an
   `input.md` is lossy; nuance survives in main agent's own writing.
3. **Loss of fresh-eyes**: current spec-review is `agd`'s first read.
   If `agd` also wrote the spec, the review's independence is gone
   unless dispatch routing guarantees different agents — extra
   complexity.
4. **Harder failure debugging**: spec defect tracing splits into
   "input.md unclear" vs "agd misread" — one more layer.
5. **No user demand**: both AI reflections targeted dispatch-layer
   stability and reviewer behavior, not orchestrator-layer
   restructuring. Higher-ROI ideas remain unimplemented.

### 11.4 Middle path (not recommended, recorded)

- **Partial**: keep brainstorming spec-writing local (preserves user
  fidelity), but dispatch the **review-driven fix application**. Lower
  risk, smaller gain.
- **input-contract trial**: at brainstorming end, produce
  `spec-input.md` (decisions, options, consensus) alongside the spec.
  Validates whether such a contract can losslessly represent
  decisions, lowering future implementation bar without committing
  now.

### 11.5 Recommendation

**Do not implement in this milestone.** Reasons in order:

1. User-dialogue fidelity outweighs token saving (§11.3.1–2).
2. Fresh-eyes risk real; needs cross-agent isolation in `agd` config.
3. The A1–A4 + TaskCreate optimizations in this spec are not yet
   validated. Measure their real token saving first before pursuing
   further restructuring.
4. YAGNI — no concrete user pain demands this; estimated benefit is
   speculative.

**Future re-evaluation triggers** (recorded so a later session knows
when to revisit):

- After A–C optimizations are live, main-agent tokens still > 100k per
  session.
- ≥ 2 independent user reports asking for this capability.
- `agd` gains cross-agent routing guaranteeing writer/reviewer agent
  isolation.

**No reserved hooks** (per scope decision Q8): reviewer templates and
wrapper script do not need extension points for this idea today.
