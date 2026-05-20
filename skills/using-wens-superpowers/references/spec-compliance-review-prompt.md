# Spec Compliance Review (per-task)

You are reviewing whether a just-implemented task matches the design spec.

- Spec: `{{spec_path}}`

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

## Your job

Compare the actual changes in those files to what the spec requires for this task. Specifically:

1. **Coverage** — every behavior the spec requires for this slice is present.
2. **No extras** — the implementation does not add features, flags, or behavior beyond the spec/task.
3. **Contracts** — output formats, env vars, file paths, exit codes match the spec exactly.
4. **No fabrication** — the implementer did not invent functionality that the spec did not call for.

Read the files via your filesystem tools (the dispatched agent has read access to `{{spec_path}}` and the files listed in `files_changed`). Do not rely on commit messages alone.

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
