---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Orchestrated Mode: Plan Verification Loop

When the agent is running inside a `using-wens-superpowers` session (the orchestrator skill loaded this skill via auto-chain and declared `WENS_ORCHESTRATED=1` + `WENS_MODE=a|b` at session entry — the marker is carried by agent context, **not** by shell environment variables, since Bash tool calls do not share shells), run an external plan-vs-spec consistency check after Self-Review and **before** the Execution Handoff. Same loop shape as brainstorming's spec-review loop.

**Behavior reference.** The dispatch wrapper (`scripts/dispatch.sh`) handles timeout tiers, empty-output retry, and slug sanitization on its own. The reviewer prompt templates handle scope guard, severity vocabulary, and R2+ verify-only on their own. Main-agent responsibilities are limited to:

1. Rendering placeholders (`{{spec_path}}`, `{{plan_path}}`, `{{stage}}`, `{{plan_task_headers}}`, `{{round}}`, `{{prev_round}}`, `{{r1_issues_inline}}`).
2. Stripping the unused round-block (Round-1 strips R2-PLUS-BLOCK; R2+ strips ROUND-1-BLOCK).
3. Parsing reviewer out.md (tolerant rules above).
4. Editing the plan file inline to apply confirmed findings.
5. Deciding loop exit (PASS) vs continue (ISSUES_FOUND).
6. Surfacing the round-10 gate via `AskUserQuestion`.

**Loop body, round N (starts at 1, resets each fresh entry to writing-plans):**

1. Render `skills/using-wens-superpowers/references/plan-verify-prompt.md` by substituting `{{spec_path}}` (absolute), `{{plan_path}}` (absolute), `{{round}}` (`N`), and `{{stage}}` (the literal string `plan`). For round 2+, also substitute `{{prev_round}}` (`N-1`) and `{{r1_issues_inline}}` (extracted issues block from the previous out.md). Substitute inline — read the template with the Read tool, perform string substitution in your own context, do not run `sed`. When rendering `plan-verify-prompt.md`, populate `{{plan_task_headers}}` with the output of `rg '^## Task ' <plan-file>`. This gives the reviewer scope context (used in the scope guard block).
2. Pipe the rendered prompt to `skills/using-wens-superpowers/scripts/dispatch.sh plan-verify-r$N` via stdin. Tier default is 1200s (20 min) for plan-verify; set `WENS_DISPATCH_TIMEOUT` only to override.
3. The Bash tool's stderr output will contain `prompt=<path>` and `out=<path>` lines. Parse them. Then Read the `out=<path>` file.
4. Parse the leading YAML frontmatter for `status`.
   - `status: PASS` → exit loop, proceed to Execution Handoff.
   - `status: ISSUES_FOUND` → for each issue, edit the plan file inline (you, the main agent, do the rewrites — do NOT dispatch them). Increment `N`. Repeat.
   - Frontmatter missing or malformed → `dispatch.sh` retries empty / no-frontmatter output internally (stderr will show `retry=1`). Treat the post-retry result as `ISSUES_FOUND` with a synthetic issue noting the format violation. Main agent retries only on non-zero exit or post-retry format violation. On second failure surface to user via `AskUserQuestion`.

From round 2 onward, the template enforces verify-only mode: new findings allowed only at severity `blocker`. The main agent strips the `<!-- ROUND-1-BLOCK -->...<!-- /ROUND-1-BLOCK -->` from the rendered template and keeps only `<!-- R2-PLUS-BLOCK -->...<!-- /R2-PLUS-BLOCK -->`. R1 issues are passed inline via `{{r1_issues_inline}}` — main agent extracts the issues section from the previous out.md and substitutes before dispatch. `{{prev_round}}` substitutes to `{{round}} - 1` as integer string.

Parse out.md leniently: strip ```yaml fences if present; treat non-{blocker,major,minor} severities as `minor`; missing frontmatter → `ISSUES_FOUND` with synthetic format-violation issue.

5. **Round 10 gate:** if `N` reaches 10 without `PASS`, use `AskUserQuestion` to ask the user: continue (resets counter, allows another 10), pause (return control), or accept-as-is (treat as PASS). Do not loop past 10 without user direction.

**Execution Handoff in orchestrated mode:** Do NOT call `AskUserQuestion` for execution mode. Auto-select Subagent-Driven (subagent-driven-development) — the orchestrator already collected the `WENS_MODE=a|b` choice at session start, and subagent-driven-development branches on that internally.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:executing-plans
- Batch execution with checkpoints for review
