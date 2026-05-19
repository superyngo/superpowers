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
