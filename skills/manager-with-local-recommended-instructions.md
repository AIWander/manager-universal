---
name: manager-with-local-recommended-instructions
description: User-facing instruction snippet for enabling breadcrumb-tracked manager delegations
version: 1.0.0
type: recommended-instructions
requires: [manager, local]
---

# Manager + Local — Recommended Instructions

> **Requires:** Both `manager` and `local` MCP servers installed.
> Copy the markdown block below into your CLAUDE.md, Claude Desktop custom
> instructions, or a project's custom instructions.

---

```markdown
## Manager + Local: Breadcrumb-Tracked Delegations

When delegating multi-step work through manager (3+ task_submit calls,
task_run_parallel, workflow_run, or multi-turn session_start), wrap the
orchestration in local's breadcrumb tracking:

- **Before first delegation:** `local:breadcrumb_start` with a title
  including concrete targets (file paths, module names) and planned steps.
  Title pattern: `"<verb> <what> | targets: <file1>, <file2>"`.
  Vague titles like "fix things" or "delegation" are rejected.

- **After each task completes:** `local:breadcrumb_step` with step name,
  result, status, and `files_changed` extracted from the task output.
  Log failed tasks too — never skip a failed step.

- **When all delegations complete:** `local:breadcrumb_complete` with a
  summary of files changed and outcomes.

- **On failure or abandonment:** `local:breadcrumb_abort` with what
  succeeded, what failed, and what was not started.

- **On session start:** `local:breadcrumb_status` to check for active
  breadcrumbs from a prior context. Resume or abort — don't ignore.

Skip wrapping for single task_submit calls or work under ~2 minutes.
One active breadcrumb at a time — complete or abort before starting another.
Never leave orphan breadcrumbs.

Full skill reference: `releases/skills/manager-with-local.md`
```

---

## What This Enables

When these instructions are active, Claude will:

1. Track multi-step delegation chains on disk via local's breadcrumb system
2. Populate `files_changed` on each step so resumption knows what was touched
3. Check `breadcrumb_status` on session start for in-progress chains
4. Handle interruptions by completing or aborting the current breadcrumb
5. Log failures as explicit steps, not silent gaps

The result: delegation chains survive context resets, agent handoffs, and
Desktop restarts. Any Claude context can call `breadcrumb_status` and pick
up where the previous session left off.

## When to Remove

Remove these instructions if:
- You uninstall either `manager` or `local`
- You prefer untracked delegations for speed on small tasks
- You're only using manager for single-shot `task_submit` calls
