---
name: manager-with-local
description: Wrapping manager delegations in local breadcrumbs for cross-context operation tracking when both servers are installed
version: 1.0.0
triggers:
  - delegate with tracking
  - manager breadcrumb
  - tracked delegation
  - manager local wrap
  - multi-step delegation
  - delegation chain
  - long-running task
  - cross-context delegation
server: manager + local
platform: windows
audience: MCP builders running both manager and local servers
---

# Manager + Local — Delegation Wrapping Skill Reference (v1.0.0)

## Overview

When you have both `manager` and `local` installed, wrap multi-step manager
delegation chains inside local breadcrumbs. The result: crash-recoverable,
cross-context, auditable delegation chains.

**This is a Claude-behavior skill.** No code integration between the servers.
Claude calls local's breadcrumb tools at the right moments to wrap manager
orchestrations in a tracked operation. The discipline is in Claude's behavior.

Without wrapping, a delegation chain is invisible context-window state. Context
resets — the chain is gone. With wrapping, the breadcrumb is on disk. Any agent
calls `breadcrumb_status` and sees: what the chain is doing, which steps
completed, which files changed, what comes next.

---

## When to Wrap

**Wrap when ALL are true:**
1. 3+ manager tasks as part of a coordinated effort
2. Total expected duration exceeds ~2 minutes
3. Work may need resuming in a different context

| Situation | Wrap? |
|-----------|-------|
| 4-task refactor across 3 files | Yes |
| `task_run_parallel` with a loaf | Yes |
| `session_start` for iterative implementation | Yes |
| Build pipeline: compile → test → deploy | Yes |
| Any delegation with `depends_on` chains | Yes |

## When NOT to Wrap

| Situation | Wrap? |
|-----------|-------|
| Single `task_submit(wait=true)` | No — done in seconds |
| Gemini Q&A delegation | No — no side effects |
| Quick codex task under 2 minutes | No — overhead exceeds value |
| Single `session_send` correction | No — inside existing session |
| Two independent `task_submit` calls | No — under 3-step threshold |

---

## The Wrapping Sequence

```
1. local:breadcrumb_start     — BEFORE the first manager call
2. manager:task_submit/etc    — the actual delegation
3. local:breadcrumb_step      — AFTER each delegated unit completes
4. Repeat 2-3 for each delegation
5. local:breadcrumb_complete  — when all delegations done
```

### Start the Breadcrumb

Before the first manager call. Not after. Not during.

```
local:breadcrumb_start(
  title="Refactor auth module | targets: src/auth/jwt.py, src/auth/session.py, tests/test_auth.py",
  steps=["implement JWT middleware", "write tests", "update compat shim", "integration test"]
)
```

### Log Each Completion

After each task completes, immediately `breadcrumb_step`. **Always populate
`files_changed`** — this is what makes resumption work. If the task output
doesn't list files, call `manager:task_explain(task_id=...)`.

```
local:breadcrumb_step(
  step="implement JWT middleware",
  result="success — jwt.py created (145 lines), __init__.py updated",
  status="success",
  files_changed=["src/auth/jwt.py", "src/auth/__init__.py"]
)
```

### Complete

```
local:breadcrumb_complete(
  summary="Auth refactored to JWT. 4 tasks, all succeeded. Files: jwt.py, session.py, test_auth.py, __init__.py."
)
```

---

## Breadcrumb Title Discipline

Pattern: `<verb> <what> | targets: <file1>, <file2>, ...`

**Good:**
```
"Refactor auth → JWT | targets: src/auth/jwt.py, src/auth/session.py, tests/test_auth.py"
"Deploy server v2.4 | targets: servers/my-server.exe"
"Add WebSocket support | targets: src/tools/websocket.rs, src/main.rs, Cargo.toml"
```

**Bad** (useless to the next session):
```
"Fix things"          "Refactor"           "Update code"
"Run some tasks"      "Manager delegation"  "Work on the project"
```

Name the crate, module, binary, or files. Specificity is not optional.

---

## One Active Breadcrumb at a Time

Local enforces single-active. If the user interrupts with new work:

**Option A — close to done (1-2 steps left):** Finish current, then start new.

**Option B — significant work remains or new request is urgent:** Abort with
a reason that includes what completed, what remains, and files changed so far.

```
local:breadcrumb_abort(
  reason="User redirected to urgent deploy. Auth refactor on step 2/4. \
    Done: JWT middleware, tests. Remaining: compat shim, integration test. \
    Files changed: src/auth/jwt.py, tests/test_auth.py."
)
```

**Never leave an orphan.** An active breadcrumb with no recent steps looks like
a crash. Abort explicitly if abandoning.

---

## Failure Handling

**Never skip a failed step.** The failure is the most important step to record.

**1. Log it:**
```
local:breadcrumb_step(
  step="write tests",
  result="failed — codex: ImportError: no module named 'pytest_asyncio'",
  status="failed"
)
```

**2. Decide:**

| Situation | Action |
|-----------|--------|
| Recoverable (missing dep, wrong path) | `task_retry` → `breadcrumb_step` on success |
| Blocks downstream | `task_rollback` → `breadcrumb_abort` with full context |
| Non-blocking parallel branch | Log failure, continue other branches |
| Intermittent (timeout) | Retry once. Fail again → abort. |

**3. If retrying, log BOTH the failure AND retry result:**
```
local:breadcrumb_step(step="write tests", result="failed — missing pytest_asyncio", status="failed")
manager:task_retry(task_id="task_xyz", additional_context="pip install pytest-asyncio first")
local:breadcrumb_step(step="write tests (retry)", result="success — 12 tests passing", status="success",
  files_changed=["tests/test_auth.py", "requirements.txt"])
```

**4. If aborting, include what succeeded:**
```
local:breadcrumb_abort(
  reason="Tests failed after 2 retries. Done: JWT middleware (jwt.py). \
    Failed: test suite (test_auth.py). Not started: compat shim, integration. \
    Rollback applied via task_rollback."
)
```

---

## Handoff and Resumption

Breadcrumbs survive everything: Desktop restart, context reset, agent handoff,
user reopening hours later. The breadcrumb is on disk, not in any context window.

### Resume Sequence

New session, first call:
```
local:breadcrumb_status()
→ title: "Refactor auth → JWT | targets: ..."
→ completed: ["implement JWT middleware", "write tests"]
→ next: "update compat shim"
→ files_changed: ["src/auth/jwt.py", "src/auth/__init__.py", "tests/test_auth.py"]
```

Pick up at the next step. Zero rework.

### Agent Handoff

Chat started it, Code finishes it:
1. Code calls `local:breadcrumb_status`, sees the active chain
2. Code resumes at next step, continues `breadcrumb_step` logging
3. Code calls `breadcrumb_complete` when done

The breadcrumb IS the handoff artifact for delegation chains.

---

## Worked Example: 4-Step Auth Refactor

User: "Refactor auth to JWT. Update middleware, write tests, add backward
compat, run integration tests."

```
# 1. Start breadcrumb
local:breadcrumb_start(
  title="Refactor auth → JWT | targets: src/auth/jwt.py, src/auth/session.py, tests/test_auth.py",
  steps=["implement JWT middleware", "write test suite", "update compat shim", "integration tests"]
)

# 2. First delegation
task_1 = manager:task_submit(
  prompt="Create JWT auth middleware in src/auth/jwt.py. HS256, extract user_id+roles, \
    401 on invalid/expired, config via JWT_SECRET + JWT_EXPIRY_SECONDS env vars.",
  backend="claude_code", working_dir="C:/project"
)
manager:task_watch(task_ids=[task_1.task_id], timeout=300)

local:breadcrumb_step(
  step="implement JWT middleware",
  result="success — jwt.py created (138 lines), __init__.py updated",
  status="success", files_changed=["src/auth/jwt.py", "src/auth/__init__.py"]
)

# 3. Second delegation
task_2 = manager:task_submit(
  prompt="Write pytest suite for JWT middleware in tests/test_auth.py. \
    Cover: valid, expired, malformed, missing header, role extraction.",
  backend="codex", working_dir="C:/project", wait=true
)

local:breadcrumb_step(
  step="write test suite",
  result="success — test_auth.py created (89 lines), 7 cases passing",
  status="success", files_changed=["tests/test_auth.py"]
)

# 4. Third delegation
task_3 = manager:task_submit(
  prompt="Update src/auth/session.py: backward-compat shim, detect session-token \
    headers, translate to JWT. Don't break existing auth.",
  backend="claude_code", working_dir="C:/project"
)
manager:task_watch(task_ids=[task_3.task_id], timeout=300)

local:breadcrumb_step(
  step="update compat shim",
  result="success — session.py updated (+42 lines)",
  status="success", files_changed=["src/auth/session.py"]
)

# 5. Fourth delegation
task_4 = manager:task_submit(
  prompt="Run full integration tests. Verify JWT + session backward compat end-to-end.",
  backend="claude_code", working_dir="C:/project", wait=true
)

local:breadcrumb_step(
  step="integration tests",
  result="success — 23 tests passing, 0 failures",
  status="success"
)

# 6. Complete
local:breadcrumb_complete(
  summary="Auth refactored to JWT. 4 delegations (claude_code + codex), all succeeded. \
    Files: jwt.py (new), session.py (updated), test_auth.py (new), __init__.py (updated). \
    23 integration tests passing. Backward compat shim in place."
)
```

**If context reset after step 4:** New session calls `breadcrumb_status`, sees
3 steps done, next is "integration tests." Submits that one delegation, logs
the step, completes the breadcrumb. Three steps preserved, zero repeated.

---

## Combining with Loafs

Loaf = manager-level coordination (subtask DAG, dependencies, decisions).
Breadcrumb = local-level tracking (step log, files_changed, crash recovery).
Use both when doing `task_run_parallel` with a loaf:

```
local:breadcrumb_start(title="Auth rewrite | targets: src/auth/*.py", steps=["submit", "watch", "close"])
loaf = manager:create_loaf(name="Auth Rewrite", goal="JWT migration")
manager:task_run_parallel(loaf_id=loaf.id, tasks=[...])
local:breadcrumb_step(step="submit", result="4 tasks submitted", status="success")
manager:task_watch(task_ids=[...], timeout=600)
local:breadcrumb_step(step="watch", result="all 4 complete", status="success", files_changed=[...])
manager:loaf_close(loaf_id=loaf.id, summary="...")
local:breadcrumb_complete(summary="Auth rewrite done. Loaf coordinated 4 tasks, all succeeded.")
```

---

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Wrap a single `task_submit(wait=true)` | Just submit — overhead exceeds value |
| Start breadcrumb AFTER first task_submit | Breadcrumb first, always |
| Use vague titles ("delegation chain") | Include targets: file paths, module names |
| Skip `breadcrumb_step` for failed tasks | Log failures — most valuable for resumption |
| Leave `files_changed` empty | Extract from task output or `task_explain` |
| Start second breadcrumb without closing first | One active. Complete or abort first. |
| Use breadcrumb as replacement for loaf | Breadcrumb tracks operation; loaf coordinates dependencies |
| Leave orphan breadcrumb when abandoning | `breadcrumb_abort` with reason, always |
| Resume without `breadcrumb_status` first | Status first, understand state, then act |
| Log step before confirming task completion | Wait for `task_watch` — don't log success prematurely |

---

## Troubleshooting

### "breadcrumb_status shows a delegation I didn't start"
Previous session crashed. Check completed steps. Resume, abort, or check
`manager:task_list` for still-running tasks.

### "Task completed but I forgot to breadcrumb_step"
Call `manager:task_explain(task_id=...)`, log retroactively. Order matters
less than completeness.

### "Files in breadcrumb look wrong"
Task wrote to unexpected paths. Check `manager:task_output`, `task_rollback`
if needed, re-delegate with clearer constraints.

### "Have both a loaf and breadcrumb — which is truth?"
Loaf = task-level detail. Breadcrumb = operation-level progress. Trust each
for its domain.

### "Breadcrumb active but all tasks finished"
Context crashed between `task_watch` return and `breadcrumb_complete`. Check
`manager:task_list`, log missing steps retroactively, complete the breadcrumb.

---

## Quick Reference Card

```
WRAP RULE:  3+ delegated steps → breadcrumb BEFORE first manager call
TITLE:      "<verb> <what> | targets: <file1>, <file2>, ..."
SEQUENCE:   breadcrumb_start → manager calls → breadcrumb_step each → breadcrumb_complete
FAILURE:    Log failed step → retry/abort → log retry result
RESUME:     breadcrumb_status → read completed/next → pick up
INTERRUPT:  Complete current OR breadcrumb_abort with reason
ONE RULE:   One active breadcrumb at a time. Always.
```

**Breadcrumb before delegation. Log every step including failures. Include files_changed. Never leave orphans.**
