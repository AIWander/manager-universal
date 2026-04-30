# manager-universal

[![CI](https://github.com/AIWander/manager-universal/actions/workflows/ci.yml/badge.svg)](https://github.com/AIWander/manager-universal/actions/workflows/ci.yml)

Multi-vendor AI orchestration from inside any MCP client. Routes coding,
reasoning, and toolchain tasks to **Claude Code**, **OpenAI Codex**,
**Google Gemini CLI**, or **OpenAI GPT API** -- based on task shape,
historical success rates, and explicit user choice.

One MCP server. Four backends. Server-side blocking. Durable coordination.

**manager-universal** is the universal-portability distribution of
[manager](https://github.com/AIWander/manager), combining:
- v1.4 reliability fixes (retry budget, stall recovery, PID-liveness watchdog)
- All v1.3.5-v1.4.5 polish from the main repo
- Zero hardcoded user paths -- resolves everything via env vars or platform defaults
- Dual-source breadcrumb reading (ops + local server dirs)

**Part of [CPC](https://github.com/AIWander) (Copy Paste Compute)** --
a multi-agent AI orchestration platform. Related repos:
[local](https://github.com/AIWander/local) -
[hands](https://github.com/AIWander/hands) -
[workflow](https://github.com/AIWander/workflow) -
[cpc-paths](https://github.com/AIWander/cpc-paths)

---

## What's New in v1.0.0

**Reliability fixes (not in main manager repo):**

- **Retry budget** -- `max_retries` defaults to 1 (not unlimited). When a task
  exhausts its budget it transitions to `failed_max_retries` and stops. Budget
  is inherited by retry tasks so escalation chains stay bounded.
- **Destructive-task safety** -- new `stall_recovery: auto | manual` field on
  every task. Prompts containing destructive keywords (`git push`, `cargo build`,
  `docker push`, etc.) default to `manual` -- stalls notify the user and wait
  for `resume_task` instead of auto-retrying. Explicit `stall_recovery` param
  overrides the heuristic.
- **PID-liveness stall watchdog** -- replaced time-based output-silence
  detection (false positives on slow tools like cargo builds) with direct child
  process liveness checks via sysinfo. Only kills tasks whose process is
  confirmed dead, not just quiet.
- **Retry backoff** -- fixed 12-minute settle window before retry fires
  (was immediate). PID-dead is definitive; immediate retry usually just re-stalls.

**From main repo (v1.3.5-v1.4.5):**

- JSON-RPC notification envelope fix (silences Claude Desktop Zod errors)
- Dashboard port bind retries 100 ports with random jitter
- Embedded-only dashboard (no stale disk override)
- Codex `--` defensive separator on all 6 arg-building sites
- Recovery notify runs in background thread (no MCP init block)
- Restart recovery persists status to disk (no notify-storm on restart)
- Per-reason notification icons ([Error] / [Warning] / [Info])
- Notification label override scoped to Done only
- Dashboard: LOAFS panel fallback to active breadcrumb count
- Dashboard: COMPLETED TODAY panel data source wired correctly
- Reconnect orphaned tasks on restart
- Dashboard port default 9218
- Dashboard URL written to `%LOCALAPPDATA%\manager-mcp\dashboard_url.txt`
- Path migration -- all user-home/workspace/volumes paths via env vars

See [CHANGELOG.md](CHANGELOG.md) for full history.

---

## Dashboard URL

The dashboard runs at `http://127.0.0.1:{port}/`. Port is chosen dynamically
at startup (default `9218`, retries 100 ports with random jitter if busy).

**Three ways to find your dashboard URL:**

1. **File:** `%LOCALAPPDATA%\manager-mcp\dashboard_url.txt`
2. **MCP tool:** `manager:dashboard_status` -- returns `{port, running, url}`
3. **MCP tool:** `manager:dashboard_open` -- opens dashboard in default browser

---

## Environment Variables

All paths resolve automatically when no env vars are set. Set these to override
the defaults or if your layout differs from the platform defaults.

| Variable | Purpose | Default |
|----------|---------|---------|
| `CPC_DASHBOARD_PORT` | Pin the dashboard to a specific port | `9218` |
| `CPC_VOLUMES_PATH` | Override volumes/knowledge-base root | Auto-detected via cpc-paths |
| `CPC_WORKSPACE_ROOT` | Override workspace/source root | `C:\rust-mcp` |
| `USERPROFILE` | User home (set by Windows, override only for testing) | `C:\Users\<you>` |
| `OPS_BREADCRUMBS_DIR` | Ops server breadcrumb log directory | `%LOCALAPPDATA%\CPC\ops-data\logs` |
| `LOCAL_BREADCRUMBS_DIR` | Local server breadcrumb log directory | `%LOCALAPPDATA%\CPC\local-data\logs` |
| `MANAGER_STALL_TIMEOUT_SECS` | Stall detection timeout (legacy, now PID-based) | `600` |
| `AUTONOMOUS_DATA_DIR` | Autonomous server data dir (breadcrumb fallback) | `%LOCALAPPDATA%\autonomous` |
| `OPENAI_API_KEY` | API key for GPT backend | (none) |

---

## Quick Start

### 1. Download

Grab the latest release binary from the
[Releases page](https://github.com/AIWander/manager-universal/releases).
Two builds: `manager-universal-vX.Y.Z-x64.exe` and
`manager-universal-vX.Y.Z-aarch64.exe`.

Rename to `manager.exe` and place it somewhere on your machine.

### 2. Wire into Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "manager": {
      "command": "C:\\path\\to\\manager.exe",
      "args": [],
      "env": {}
    }
  }
}
```

Set env overrides as needed (e.g., `"CPC_DASHBOARD_PORT": "9218"`).

### 3. Restart Claude Desktop

Manager starts, binds the dashboard, and begins listening for MCP calls.
Open the dashboard URL from `%LOCALAPPDATA%\manager-mcp\dashboard_url.txt`.

---

## Building from Source

Requires Rust stable. Windows only (PowerShell toast notifications, sysinfo
PID checks use Windows APIs).

```powershell
git clone https://github.com/AIWander/manager-universal.git
cd manager-universal
cargo build --release
# binary at target\release\manager.exe
```

---

## Overview

Manager exists for the **delegate-when-the-task-gets-long** heuristic: if the
implementation needs more than ~30-40 lines of code, delegate it to a coding
agent instead of writing inline. Your chat context is for reasoning and
orchestration; coding agents have their own sandboxes and token budgets.

### The meta-agent pattern

Your primary chat (Claude Desktop, Claude Code, or any MCP client) becomes
the orchestrator -- it holds goal-level context, decides what to delegate,
when to parallelize, and how to synthesize results. Coding agents are
disposable workers. Manager sits between them as durable infrastructure:
persisting task state to disk, tailing child process logs, and reconnecting
surviving subprocesses across restarts.

Practical consequences:

- Conversation window is freed from implementation detail
- Failed delegations do not cost orchestration context -- retry with `task_retry`
- Long-running work survives client restarts
- Parallel subtasks via `task_run_parallel` -- fan out, collect, synthesize
- Multiple coding backends coexist: Claude Code for multi-step toolchains,
  Codex for one-shot scripts, Gemini for large-context Q&A

---

## Stall Recovery (v1.0.0)

Two recovery modes for when a delegated agent process dies unexpectedly:

**`stall_recovery: auto` (default for most tasks)**
- Dead process detected -> task marked `Failed` -> retry queued (up to `max_retries`)
- 12-minute backoff before retry fires (gives long CI/build tools time to settle)

**`stall_recovery: manual` (default for destructive prompts)**
- Dead process detected -> task marked `Paused` with `paused_reason: stall_manual_recovery`
- Toast notification fires: "Child process exited. Manual recovery required"
- Call `manager:resume_task` to restart, or `manager:destroy_task` to cancel
- Use this for: database migrations, force-pushes, file rewrites, deploys

Destructive-prompt heuristic triggers on: `git push`, `cargo build`, `cargo test`,
`docker build`, `docker push`, `terraform apply`, `kubectl apply`, `npm install`,
`pip install`, `make`, `format`, `delete`, `--write`.

Override heuristic by passing `stall_recovery: auto` or `stall_recovery: manual`
explicitly in `submit_task` params.

---

## Retry Budget (v1.0.0)

Default `max_retries: 1` -- one auto-retry per task. Pass `max_retries: 0` to
disable auto-retry. Pass `max_retries: 2` or higher for tasks where multiple
attempts are expected (e.g. model-inference tasks that occasionally timeout).

When budget is exhausted, task status becomes `failed_max_retries`. The task
stops and is not retried again.

On retry:
- Backend escalates (ClaudeCode -> Codex -> Gemini on successive retries)
- Effort escalates (low/medium -> high, high -> max)
- Previous error is injected into the new prompt
- `retry_of` field links back to the original task
- `retried_as` field on the original task links forward to the retry

---

## License

Apache-2.0. See [LICENSE](LICENSE).
