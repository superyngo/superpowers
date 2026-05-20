# Implement Task (Mode b — dispatched implementer)

You are implementing one task from an approved implementation plan. The main coordinator is running on a separate session and has delegated this task to you via `dispatch-agent`.

**Workspace root:** `{{repo_root}}`
**Spec:** `{{spec_path}}`
**Plan:** `{{plan_path}}`

The current stage is `{{stage}}`.

## Scope Guard (MUST FOLLOW)

ONLY review work belonging to **this specific {{stage}}**. Do NOT flag:
- Work that other tasks in the plan will handle later (see "Other tasks in plan" below).
- Pre-existing code outside what this {{stage}} changed.
- Style nits in files this {{stage}} did not touch.

When in doubt about whether a finding is in scope, omit it.

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
