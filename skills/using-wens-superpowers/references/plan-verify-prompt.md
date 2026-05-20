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
