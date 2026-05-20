# Code Quality Review (per-task)

You are reviewing the *quality* of a just-implemented task. Spec compliance has already been verified separately — focus on engineering quality.

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
