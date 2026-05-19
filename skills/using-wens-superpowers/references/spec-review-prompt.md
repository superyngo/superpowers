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
