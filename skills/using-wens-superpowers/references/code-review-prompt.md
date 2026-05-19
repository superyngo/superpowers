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
