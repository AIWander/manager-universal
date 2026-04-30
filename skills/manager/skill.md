---
name: manager
description: Multi-vendor AI orchestration MCP server — routes coding and reasoning tasks to Claude Code, Codex, Gemini, or GPT from inside any MCP client
version: 1.1.1
triggers:
  - delegate
  - task
  - codex
  - gemini
  - gpt
  - orchestrate
  - parallel
  - loaf
  - multi-agent
  - route task
  - send to
  - hand off code
  - run in background
  - who should handle
---

# Manager MCP Server — Skill Reference (v1.1.1)

Multi-vendor AI orchestration from inside any MCP client. Manager routes
coding, reasoning, and toolchain tasks to **Claude Code**, **OpenAI Codex**,
**Google Gemini CLI**, or **OpenAI GPT API** — based on task shape, historical
success rates, and explicit user choice. No Python runtime, no framework
install, no sidecar process. One MCP server, four backends, server-side
blocking, durable coordination.

---

## What's New in v1.1.1

| Change | Details |
|--------|---------|
| **`task_rerun` documented** | Re-submit a completed task with tweaked context, file injection, or backend override. See [task_rerun](#task_rerun). |
| **Stall detector fix** | Threshold raised from 30s to 90s. Detector skips mid-flight tools entirely. No more false positives on long Write/Edit operations. See [Stall Detection](#stall-detection). |
| **`health` enum on task_status** | New `health` field replaces `stall_detected` as the field to read. Values: `done`, `failed`, `queued`, `cancelled`, `paused`, `running_long_tool`, `stalled`, `idle`, `running`. See [task_status](#task_status). |
| **`active_tool_running` on task_status** | Boolean — `true` when the backend's most recent step has no completion event yet. |
| **Task lineage fields** | `parent_task_id`, `forked_from`, `continuation_of` now exist on Task records. Only `parent_task_id` is populated today (by `task_rerun`). Fork + continuation handlers land in a follow-up release. |

---

## The Delegation Discipline

This is the entire reason manager exists. Read this section first.

### The 33-Line Rule

**If the task requires writing more than ~33 lines of code, delegate it.**

Claude's context window is reasoning. Every line of code you write inline
burns tokens that should be spent thinking, planning, reviewing, and
extracting insights. Coding agents — Codex, Claude Code, Gemini — have
their own sandboxes, their own token budgets, and their own tool access.
Let them write code. You orchestrate.

The number 33 is not arbitrary. It's the empirical threshold where inline
code generation starts to crowd out the reasoning and coordination work
that makes orchestration valuable. Below 33 lines, the overhead of
delegation (prompt construction, task submission, result parsing) exceeds
the cost of just writing it. Above 33 lines, delegation wins every time.

**Practical application:**

| Situation | Action |
|-----------|--------|
| 5-line config edit | Write it inline |
| 20-line utility function | Judgment call — inline if trivial, delegate if logic-heavy |
| 40-line feature implementation | Delegate. Always. |
| 100+ line refactor | Delegate with a loaf if multi-file |
| Multi-file coordinated change | Delegate with `task_run_parallel` or a project loaf |

### Why Not Just Use Subagents?

Anthropic's built-in `Agent` tool launches subprocesses of Claude. That
works for research and exploration. But it doesn't give you:

- **Cross-vendor routing.** Codex is faster for write-and-run. Gemini is
  cheaper for one-shot Q&A. GPT excels at pure reasoning chains. Manager
  picks the right backend per task.
- **Server-side blocking.** `task_watch` blocks on the server until tasks
  complete. Zero polling turns, zero wasted LLM calls checking status.
- **Durable coordination.** Project Loafs are JSON files on disk. They
  survive context resets, session crashes, and agent handoffs.
- **Archive-first safety.** Every delegated task that touches files creates
  a backup before writing. `task_rollback` restores from that backup.
- **Historical learning.** `get_analytics` shows which backends succeed at
  which task types over time. The auto-router uses this data.

### The Delegation Mindset

When you receive a task:

1. **Decompose.** Break it into units of work. Each unit should be
   completable by a single backend in a single pass.
2. **Classify.** Is this coding, reasoning, Q&A, or multi-step toolchain?
3. **Route.** Pick a backend (or let `auto_route` pick). Submit.
4. **Monitor.** Use `task_watch` for blocking waits, `task_status` for
   quick checks.
5. **Extract.** When the result comes back, scan it for corrections,
   decisions, and discoveries worth capturing.

---

## Backend Selection

### Auto-Route (Recommended Default)

```
task_submit(prompt="...", auto_route=true)
```

When you're unsure which backend fits, use `auto_route`. The router
evaluates:

- **Task shape:** Code generation vs reasoning vs Q&A vs multi-tool
- **Historical success rates:** Per-backend hit rates for similar task types
- **Current availability:** Backend health and queue depth
- **Learned patterns:** Corrections and failures feed back into routing

Auto-route is the right choice 70%+ of the time. Only override when you
have specific knowledge about backend fit.

### Manual Backend Selection

Override auto-route when the task clearly maps to a backend's strength:

#### Codex (`backend="codex"`)
- **Best for:** Single-file write-and-run, code generation with tests,
  quick script creation, file transformations
- **Strength:** Fastest turnaround for bounded coding tasks
- **Weakness:** No multi-step toolchain access, no interactive correction
- **Use when:** "Write this function" or "Create this script"

#### Claude Code (`backend="claude_code"`)
- **Best for:** Multi-step toolchain work, tasks requiring tool access,
  iterative implementation with corrections, complex refactors
- **Strength:** Full MCP tool access, multi-turn correction capability
- **Weakness:** Slower startup, higher token cost
- **Use when:** "Implement this feature across these files" or "Debug this
  failing test by reading logs and fixing code"

#### Gemini (`backend="gemini"`)
- **Best for:** One-shot Q&A, large-context analysis, document summarization,
  quick factual lookups
- **Strength:** Fast, cheap, handles massive context windows
- **Weakness:** Less reliable for complex multi-step coding
- **Use when:** "Analyze this log file" or "Summarize these 50 test results"

#### GPT (`backend="gpt"`)
- **Best for:** Pure reasoning chains, structured output generation,
  classification, decision trees
- **Strength:** Strong logical reasoning, consistent structured output
- **Weakness:** No direct file system access via manager
- **Use when:** "Classify these 20 error messages" or "Generate a decision
  matrix for these options"

---

## Tool Reference

### Task Tools (Core)

#### `task_submit`
Submit a one-shot task to a backend.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prompt` | Yes | The task description and any context |
| `backend` | No | `auto_route`, `codex`, `claude_code`, `gemini`, `gpt` (default: `auto_route`) |
| `wait` | No | `true` to block until complete (default: `false`) |
| `working_dir` | No | Directory for the backend to operate in |
| `context` | No | Additional context string injected into the backend prompt |
| `tags` | No | Array of tags for analytics grouping |

**`wait=true` vs fire-and-forget:**

- **`wait=true`:** Use for short tasks (under ~5 minutes) where you need the
  result in this turn. The MCP call blocks until the backend returns.
  Simple, synchronous, no polling overhead.

  ```
  task_submit(prompt="Write a pytest for utils.py", backend="codex", wait=true)
  ```

- **`wait=false` (default):** Returns a `task_id` immediately. Use for
  longer work where you want to do other things while the backend works.
  Check with `task_status` or block with `task_watch`.

  ```
  result = task_submit(prompt="Refactor the auth module", backend="claude_code")
  # result.task_id = "task_abc123"
  # ... do other work ...
  task_watch(task_ids=["task_abc123"])
  ```

#### `task_status`
Check the current state of a submitted task.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The task ID from `task_submit` |

Returns: status (`pending`, `running`, `complete`, `failed`), output if
complete, error if failed, elapsed time, plus:

| Field | Type | Description |
|-------|------|-------------|
| `health` | string | **Read this field for behavior decisions.** Values: `done`, `failed`, `queued`, `cancelled`, `paused`, `running_long_tool`, `stalled`, `idle`, `running`. More expressive than raw status. |
| `active_tool_running` | bool | `true` when the backend's most recent step is `"started"` with no completion event yet. A tool is mid-flight. |
| `stall_detected` | bool | Legacy. Still present for backward compat. Prefer `health` — it distinguishes `running_long_tool` (safe to wait) from `stalled` (actually stuck). |

##### Stall Detection

Previous behavior: flagged `stall_detected: true` after 30 seconds of no
activity. This caused false positives — a Write operation on a 12KB markdown
file once took 99 seconds between visible step updates and was incorrectly
flagged as stalled.

Current behavior (v1.1.1):
- Threshold raised to **90 seconds**
- Detector **skips entirely** when a tool is mid-flight (`active_tool_running == true`)
- A tool is mid-flight when `task.steps.last().status == "started"` (no completion event yet)

**Bottom line:** When `health` says `running_long_tool`, the backend is working.
Wait. Do not cancel.

#### `task_watch`
Server-side block until one or more tasks complete. **This is the
zero-polling-overhead way to wait.**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_ids` | Yes | Array of task IDs to watch |
| `timeout` | No | Max seconds to wait (default: 300) |

Returns when ALL watched tasks reach a terminal state (`complete` or
`failed`). No LLM turns consumed while waiting. The server holds the
connection.

```
# Watch multiple tasks at once
task_watch(task_ids=["task_1", "task_2", "task_3"], timeout=600)
```

#### `task_output`
Retrieve the full output of a completed task.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The task ID |

#### `task_cancel`
Cancel a running or pending task.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The task ID |

#### `task_retry`
Re-run a failed task with the original prompt PLUS the error message
injected as context. The backend sees what went wrong and avoids repeating
the same mistake.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The failed task's ID |
| `additional_context` | No | Extra guidance beyond the auto-injected error |

```
# Task failed because it tried to import a missing module
task_retry(task_id="task_abc", additional_context="Use pandas, not polars — polars is not installed")
```

#### `task_rerun`
Re-submit a completed task using its original prompt, with optional
modifications. The new task links back to the original via `parent_task_id`
(set automatically via `rerun_of`).

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The completed task to re-run |
| `additional_context` | No | Extra context appended to the original prompt |
| `include_files` | No | Array of file paths to inject into the backend prompt |
| `backend_override` | No | Run on a different backend than the original |

Returns a new `task_id`. The new task record contains a `rerun_of` field
pointing to the original.

**`task_rerun` vs `task_retry`:**

- **`task_retry`** — for *failed* tasks. Auto-injects the error message so the
  backend avoids the same mistake.
- **`task_rerun`** — for *completed* tasks that need another pass. Maybe the
  output was 90% right but needs a tweak, or you want the same work done with
  a different backend or additional files.

```
# Original task produced good code but missed edge cases
task_rerun(
  task_id="task_abc",
  additional_context="Also handle the case where input is an empty array",
  include_files=["tests/edge_cases.py"]
)
```

#### `task_rollback`
Restore file state from before a failed task. Archive-first means backups
were created when the task started writing files. Rollback restores from
those backups.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The task ID whose file changes to revert |

#### `task_explain`
Get a human-readable summary of what a task did, including files changed,
commands run, and key decisions.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task_id` | Yes | The task ID |

#### `task_list`
List recent tasks with optional filtering.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `status` | No | Filter by status |
| `backend` | No | Filter by backend |
| `limit` | No | Max results (default: 20) |

#### `task_cleanup`
Remove completed/failed task records older than a threshold.

#### `task_decompose`
Break a complex prompt into subtasks suitable for parallel execution.
Returns a suggested task DAG.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prompt` | Yes | The complex task to decompose |

#### `task_route`
Ask the router which backend it would pick for a prompt, without actually
submitting. Useful for understanding routing decisions.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prompt` | Yes | The task to evaluate |

### Session Tools (Multi-Turn)

Use sessions when you need back-and-forth with a backend — corrections,
follow-ups, iterative refinement.

#### `session_start`
Start a persistent session with a backend.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `backend` | Yes | Which backend to connect |
| `working_dir` | No | Working directory |
| `system_prompt` | No | System-level instructions for the session |

Returns a `session_id` for subsequent interactions.

**When to use sessions vs tasks:**

- **`task_submit`:** One-shot. "Write this function." Done.
- **`session_start`:** Multi-turn. "Implement this feature. Now fix the
  test. Now update the docs." Back-and-forth until satisfied.

#### `session_send`
Send a message to an active session.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `session_id` | Yes | The session ID |
| `message` | Yes | Your message to the backend |

#### `session_list`
List active sessions with their backends and status.

### Project Loaf Tools (Coordination)

A **Project Loaf** is a persistent JSON coordination file on disk. When you
have 2+ delegated subtasks working toward a shared goal, create a loaf.
The loaf tracks:

- Overall goal and status
- Individual subtask states
- Dependencies between subtasks
- Shared context accessible to all subtasks
- Completion criteria

Loafs survive context resets and agent handoffs. They are the durable
coordination primitive.

#### `create_loaf`
Create a new project loaf.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `name` | Yes | Human-readable loaf name |
| `goal` | Yes | What this coordination achieves |
| `subtasks` | No | Initial subtask definitions |

#### `loaf_update`
Update loaf state — mark subtasks complete, add context, update status.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `loaf_id` | Yes | The loaf ID |
| `updates` | Yes | Object with fields to update |

#### `loaf_status`
Read current loaf state.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `loaf_id` | Yes | The loaf ID |

#### `loaf_close`
Mark a loaf as complete. Finalizes the coordination record.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `loaf_id` | Yes | The loaf ID |
| `summary` | No | Final summary of what was accomplished |

### Workflow Tools (DAG Execution)

#### `task_run_parallel`
Execute multiple tasks with dependency gates and parallel groups.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `tasks` | Yes | Array of task definitions with `depends_on` fields |
| `loaf_id` | No | Attach all tasks to a project loaf |

Each task in the array can specify:
- `id`: Local reference ID for dependency edges
- `prompt`: The task prompt
- `backend`: Backend selection (default: `auto_route`)
- `depends_on`: Array of task `id`s that must complete first

```
task_run_parallel(tasks=[
  { id: "tests",    prompt: "Write unit tests for auth.py",     backend: "codex" },
  { id: "docs",     prompt: "Write docstrings for auth.py",     backend: "gemini" },
  { id: "refactor", prompt: "Refactor auth.py using new tests",
                     backend: "claude_code", depends_on: ["tests"] },
  { id: "review",   prompt: "Review the refactored auth.py",
                     backend: "gpt", depends_on: ["refactor", "docs"] }
])
```

Tasks with no dependencies run immediately in parallel. Tasks with
`depends_on` wait until all dependencies reach a terminal state.

#### `workflow_run`
Execute a named, saved workflow template.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `template` | Yes | Template name |
| `params` | No | Parameter overrides |

#### `template_save` / `template_list` / `template_run`
Save, list, and run reusable workflow templates.

### Analytics Tools

#### `get_analytics`
Query historical task performance data.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `period` | No | Time window: `day`, `week`, `month` (default: `week`) |
| `backend` | No | Filter to one backend |
| `tag` | No | Filter by task tag |

Returns: success rates per backend, average completion times, failure
categories, routing accuracy (auto_route picks vs optimal picks).

Use this to understand which backends work for which task types over time.
Feed insights back into manual routing decisions.

### Configuration Tools

#### `configure`
Update manager settings at runtime.

#### `role_create` / `role_delete` / `role_list`
Define named roles with pre-set backend preferences and system prompts.
Roles let you create reusable backend configurations like "fast-coder"
(Codex with specific instructions) or "careful-reviewer" (GPT with review
prompts).

### Extraction Tools

#### `review_extractions` / `dismiss_extraction` / `extract_workflow`
After delegated work completes, review the output for patterns, decisions,
and corrections worth extracting to the knowledge base.

---

## Common Patterns

### Pattern 1: Single-Task Delegation

The simplest case. You have one coding task, delegate it, get the result.

```
# Short task — use wait=true
result = task_submit(
  prompt="Add input validation to user_create() in api/users.py. \
          Validate email format and password length >= 12.",
  backend="codex",
  wait=true
)
# Result is immediately available. Review it, extract insights if any.
```

### Pattern 2: Multi-Turn Session

You need iterative refinement — implement, test, fix, test again.

```
# Start a session with Claude Code (best for multi-step)
session = session_start(backend="claude_code", working_dir="C:/project")

# First instruction
session_send(session_id=session.id, message="Implement the caching layer per spec.md")

# Review output, send correction
session_send(session_id=session.id, message="The TTL should be configurable, not hardcoded. Use env var CACHE_TTL_SECONDS.")

# Final step
session_send(session_id=session.id, message="Add tests for the TTL override path.")
```

### Pattern 3: Parallel Workflow with Dependencies

Multiple tasks, some parallel, some sequential.

```
# Create a loaf for coordination
loaf = create_loaf(
  name="Auth Module Rewrite",
  goal="Replace session-token auth with JWT, maintain backward compat"
)

# Define the DAG
task_run_parallel(
  loaf_id=loaf.id,
  tasks=[
    { id: "jwt_impl",  prompt: "Implement JWT auth middleware in auth/jwt.py",
                        backend: "claude_code" },
    { id: "jwt_tests",  prompt: "Write pytest suite for JWT auth",
                        backend: "codex", depends_on: ["jwt_impl"] },
    { id: "migration",  prompt: "Write DB migration for jwt_secrets table",
                        backend: "codex" },
    { id: "compat",     prompt: "Add backward-compat shim: if Authorization header \
                        is session token, translate to JWT internally",
                        backend: "claude_code", depends_on: ["jwt_impl", "migration"] },
    { id: "docs",       prompt: "Update API docs to reflect JWT auth",
                        backend: "gemini", depends_on: ["compat"] }
  ]
)

# Block until everything finishes
task_watch(task_ids=[...all task ids...], timeout=900)

# Review results, close the loaf
loaf_close(loaf_id=loaf.id, summary="JWT auth deployed with backward compat and full test coverage")
```

### Pattern 4: Rollback Recovery

A task failed and left files in a bad state.

```
# Check what happened
task_explain(task_id="task_xyz")
# Output: "Modified 3 files, failed on test execution"

# Rollback file changes
task_rollback(task_id="task_xyz")

# Retry with additional context so it doesn't repeat the mistake
task_retry(
  task_id="task_xyz",
  additional_context="The test DB requires POSTGRES_URL env var. Set it before running pytest."
)
```

### Pattern 5: Backend Performance Review

Periodically check which backends are earning their keep.

```
analytics = get_analytics(period="week")

# Example insight: Codex has 95% success on single-file tasks but 40% on
# multi-file. Stop routing multi-file work to Codex.
# Gemini has 90% success on Q&A but takes 3x longer than GPT.
# Claude Code has the highest success on multi-step but costs 4x more.
```

---

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Write 80 lines of code inline | `task_submit` with `backend="codex"` — that's what it's for |
| Poll `task_status` in a loop | `task_watch` — server-side block, zero wasted turns |
| Start a session for a one-shot task | `task_submit(wait=true)` — sessions are for multi-turn |
| Submit without `working_dir` | Always set `working_dir` so the backend operates in the right place |
| Forget to scan delegation output | After `task_watch` returns, check for extraction-worthy content |
| Create parallel tasks without a loaf | If 2+ tasks coordinate, create a loaf first for durability |
| Hardcode backend for every task | Use `auto_route` as default, override only when you know better |
| Retry without context injection | `task_retry` auto-injects the error — add your own guidance too |
| Ignore `task_rollback` after failure | Archive-first exists for a reason. Use it. |
| Delegate without injecting relevant context | Read the relevant files first, include summaries in the prompt |
| Fire-and-forget long tasks then lose the task_id | Store task_ids in a loaf or note them — you'll need them |
| Use `session_start` for independent parallel work | Sessions are sequential. Use `task_run_parallel` for parallelism |
| Read `stall_detected` for behavior decisions | Read `health` instead — it distinguishes `running_long_tool` from `stalled` |
| Cancel a task showing `health: "running_long_tool"` | That means a tool is mid-flight. Wait. The backend is working. |
| Write a new prompt from scratch when a completed task needs tweaks | `task_rerun` with `additional_context` — reuses the original prompt |

---

## Troubleshooting

### Task stuck in `pending`
Backend may be unavailable. Check:
1. `task_status(task_id=...)` — look at the status detail
2. `task_route(prompt=...)` — see if the router can reach the backend
3. `task_cancel` and resubmit with a different backend

### Task failed with timeout
Default timeout is 300s. For large tasks:
- Set `timeout` on `task_watch` to a higher value
- Or break the task into smaller subtasks

### Auto-route picks the wrong backend
1. Check `get_analytics` — the router learns from history. If a backend
   recently failed at a task type, it may be down-weighted.
2. Use `task_route` to preview routing decisions without submitting.
3. Override with explicit `backend` when you know better.

### Session goes stale
Sessions can time out if idle too long.
1. `session_list` to check status
2. Start a new session if the old one is dead
3. Include context from the previous session in the new `system_prompt`

### Loaf state is inconsistent
If a crash interrupted a loaf update:
1. `loaf_status` to read current state
2. `loaf_update` to manually correct any inconsistencies
3. Tasks are independent of loaf state — a loaf being wrong doesn't
   affect running tasks

### Backend-specific issues

**Codex:** Requires `OPENAI_API_KEY` or Codex CLI configured. Single-sandbox
only — cannot access MCP tools or other servers.

**Claude Code:** Requires Claude Code CLI. Slowest to start but most
capable for multi-tool work.

**Gemini:** Requires `GEMINI_API_KEY` or Gemini CLI. Fast but may truncate
very long outputs.

**GPT:** Requires `OPENAI_API_KEY`. No direct filesystem access — results
are text only, you must apply file changes yourself.

---

## Quick Reference Card

```
DELEGATE:  task_submit(prompt, auto_route=true, wait=true)
WATCH:     task_watch(task_ids=[...], timeout=300)
ITERATE:   session_start → session_send → session_send → ...
PARALLEL:  task_run_parallel(tasks=[{id, prompt, backend, depends_on}])
COORDINATE: create_loaf → task_run_parallel(loaf_id=...) → loaf_close
RECOVER:   task_rollback(task_id) → task_retry(task_id, additional_context)
LEARN:     get_analytics(period="week")
```

**The 33-line rule. Auto-route by default. Archive-first always. Scan output for extractions.**
