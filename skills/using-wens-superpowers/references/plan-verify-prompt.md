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
