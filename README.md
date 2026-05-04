# Manager Universal — Multi-Backend AI Delegation for MCP

[![CI](https://github.com/AIWander/manager-universal/actions/workflows/ci.yml/badge.svg)](https://github.com/AIWander/manager-universal/actions/workflows/ci.yml)

A Rust MCP server that delegates coding, reasoning, and toolchain tasks to **Claude Code**, **OpenAI Codex**, **Google Gemini CLI**, or **OpenAI GPT API** through a single tool surface. One server replaces three separate MCP integrations (claude-runner, codex, gemini-mcp) with unified task lifecycle, persistent state, and a live dashboard.

Manager sits between your orchestration context and disposable coding agents. Your chat session holds goal-level reasoning; manager handles subprocess spawning, output tailing, stall detection, retry escalation, and crash recovery. Long-running delegations survive client restarts. Failed tasks retry with backend escalation. Parallel fan-out collects results without burning orchestration tokens.

**Part of [CPC](https://github.com/AIWander) (Copy Paste Compute)** — a multi-agent AI orchestration platform. Related repos: [hands](https://github.com/AIWander/hands) · [workflow](https://github.com/AIWander/workflow) · [local](https://github.com/AIWander/local) · [cpc-paths](https://github.com/AIWander/cpc-paths)

## Install

### Pre-built Binary

1. Download from the [latest release](https://github.com/AIWander/manager-universal/releases/latest):
   - **Windows x64** → `manager-universal-vX.Y.Z-x64.exe`
   - **Windows ARM64** → `manager-universal-vX.Y.Z-aarch64.exe`
2. Rename to `manager.exe` and place in `%LOCALAPPDATA%\CPC\servers\`.
3. Add to `claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "manager": {
         "command": "%LOCALAPPDATA%\\CPC\\servers\\manager.exe",
         "env": {
           "CPC_DASHBOARD_PORT": "9999",
           "CPC_VOLUMES_PATH": "C:\\My Drive\\Volumes"
         }
       }
     }
   }
   ```
4. Restart Claude Desktop.

### Build from Source

```bash
git clone https://github.com/AIWander/manager-universal.git
cd manager-universal
cargo build --release
# binary at target/release/manager.exe
```

Requires Rust stable. Windows only (toast notifications, PID-liveness checks use Windows APIs).

---

## 48 Tools

### Task Lifecycle (12 tools)

| Tool | Description |
|------|-------------|
| `task_submit` | Delegate a prompt to a backend (Claude Code, Codex, Gemini, GPT) |
| `task_status` | Get current status, output tail, and metadata for a task |
| `task_output` | Stream full stdout/stderr from a running or completed task |
| `task_list` | List all tasks with optional status/session filters |
| `task_cancel` | Kill a running task's subprocess and mark cancelled |
| `task_poll` | Long-poll for task state changes (blocks until update or timeout) |
| `pause_task` | Manually pause a running task |
| `resume_task` | Resume a paused task (restarts subprocess) |
| `task_retry` | Retry a failed task with backend/effort escalation |
| `task_rerun` | Re-run a completed task with the same or modified prompt |
| `task_rollback` | Rollback a task's file changes using git diff |
| `task_cleanup` | Remove completed/failed tasks from state |

### Session Management (5 tools)

| Tool | Description |
|------|-------------|
| `session_start` | Start a persistent interactive session with a backend |
| `session_send` | Send a follow-up message to an active session |
| `session_list` | List active sessions |
| `session_destroy` | Terminate a session and its subprocess |
| `send` | Alias for session_send with shorter syntax |

### Parallel & Routing (4 tools)

| Tool | Description |
|------|-------------|
| `task_run_parallel` | Fan out multiple prompts to backends, collect all results |
| `task_route` | Auto-route a prompt to the best backend based on task shape |
| `task_decompose` | Break a complex prompt into subtasks with dependency graph |
| `task_explain` | Explain what a task did, decisions made, files changed |

### Loaf (Task Groups) (4 tools)

| Tool | Description |
|------|-------------|
| `create_loaf` | Create a named task group with phases and acceptance criteria |
| `loaf_update` | Update loaf progress, add findings, mark phases done |
| `loaf_status` | Get current loaf state including subtask roll-up |
| `loaf_close` | Close a loaf with summary and final status |

### Templates (3 tools)

| Tool | Description |
|------|-------------|
| `template_save` | Save a reusable prompt template with variable slots |
| `template_list` | List saved templates |
| `template_run` | Execute a template with variable substitution |

### Roles (3 tools)

| Tool | Description |
|------|-------------|
| `role_list` | List available agent roles (architect, implementer, tester, etc.) |
| `role_create` | Define a custom role with system prompt and constraints |
| `role_delete` | Remove a custom role |

### Extraction & Workflow (4 tools)

| Tool | Description |
|------|-------------|
| `workflow_run` | Run a multi-step workflow (sequential task chain) |
| `review_extractions` | Review pending extraction candidates from task outputs |
| `extract_workflow` | Accept and persist an extraction |
| `dismiss_extraction` | Dismiss a pending extraction |

### Analytics & Monitoring (7 tools)

| Tool | Description |
|------|-------------|
| `status_bar` | One-line summary of active tasks, sessions, and system health |
| `task_watch` | Watch a task until completion with configurable poll interval |
| `get_analytics` | Historical stats: success rates, durations, backend comparison |
| `run_analyzer` | Run analysis passes over task history (patterns, failures) |
| `notify` | Send a Windows toast notification |
| `configure` | Get/set manager runtime configuration |
| `open_terminal` | Open a new terminal window at a given path |

### Dashboard (3 tools)

| Tool | Description |
|------|-------------|
| `dashboard_open` | Open the live dashboard in the default browser |
| `dashboard_stop` | Stop the dashboard HTTP server |
| `dashboard_status` | Get dashboard URL, port, and running state |

### Backend Shortcuts (3 tools)

| Tool | Description |
|------|-------------|
| `gemini_direct` | One-shot Gemini CLI call without full task lifecycle |
| `codex_exec` | One-shot Codex call without full task lifecycle |
| `codex_review` | Codex code review on a file or diff |

---

## Dashboard

The embedded dashboard runs at `http://127.0.0.1:{port}/` during any active session. Default port is `9218`; pin it with `CPC_DASHBOARD_PORT`. Zones:

- **Sessions** — active backend sessions with PID, uptime, last activity
- **Active Loafs** — task groups in progress with phase completion
- **Active Operations** — running tasks with live output tails
- **Last 5 Tools** — recent MCP tool calls with timing
- **Retry Chains** — chevron-linked retry sequences showing escalation path

Find your URL: `dashboard_status` tool, or read `%LOCALAPPDATA%\manager-mcp\dashboard_url.txt`.

---

## Backends

| Backend | Strengths | Typical Use | Speed | Cost |
|---------|-----------|-------------|-------|------|
| **Claude Code** | Multi-file edits, tool use, deep reasoning, iterative refinement | Refactors, new features, complex debugging | Medium (30-120s) | High |
| **Codex** | One-shot code generation, fast turnaround, good at scripts | Single-file tasks, quick fixes, reviews | Fast (5-20s) | Low |
| **Gemini CLI** | Large context window (1M tokens), broad knowledge | Large-context Q&A, doc synthesis, exploration | Medium (15-60s) | Low |
| **GPT API** | Structured output, function calling, flexible models | Analysis, classification, structured extraction | Fast (3-15s) | Medium |

Backend escalation on retry: Claude Code → Codex → Gemini. Effort escalation: low → medium → high → max.

---

## Auto-Pause & Safety

Manager includes a **destructive-command heuristic** that auto-classifies prompts containing keywords like `git push`, `docker push`, `terraform apply`, `cargo build`, `npm install`, `delete`, `--write` as potentially destructive.

These tasks default to `stall_recovery: manual` — if the subprocess dies, the task pauses instead of auto-retrying. A toast notification fires and the task waits for `resume_task` or `task_cancel`. Paused tasks aren't failures; check `paused_reason` and decide.

Override per-task: pass `stall_recovery: auto` to force auto-retry, or `stall_recovery: manual` on any task for extra safety.

Retry budget: `max_retries` defaults to 1. Exhausted budget → `failed_max_retries` status (task stops permanently). Previous error context is injected into retry prompts.

---

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CPC_DASHBOARD_PORT` | Pin dashboard to a specific port | `9218` |
| `CPC_VOLUMES_PATH` | Knowledge-base root path | Auto-detected via cpc-paths |
| `CPC_WORKSPACE_ROOT` | Source/workspace root | `C:\rust-mcp` |
| `OPS_BREADCRUMBS_DIR` | Ops server breadcrumb directory | `%LOCALAPPDATA%\CPC\ops-data\logs` |
| `LOCAL_BREADCRUMBS_DIR` | Local server breadcrumb directory | `%LOCALAPPDATA%\CPC\local-data\logs` |
| `OPENAI_API_KEY` | API key for GPT backend | (none) |

---

## Related Repos

| Repo | What it does |
|------|-------------|
| [hands](https://github.com/AIWander/hands) | Browser, UIA, and vision desktop automation (117 tools) |
| [workflow](https://github.com/AIWander/workflow) | API discovery, credential vault, data pipelines, watches (37 tools) |
| [local](https://github.com/AIWander/local) | Filesystem, shell, git, transforms, sessions |
| [autonomous](https://github.com/AIWander/autonomous) | Knowledge engine, extractions, Volumes, learning |
| [voice-mcp](https://github.com/AIWander/Voice-Command) | Voice input/output for MCP agents |

---

## Contributing

Issues welcome; PRs considered but this is primarily maintained as part of the CPC stack.

## License

Apache 2.0 — see [LICENSE](LICENSE).

Copyright 2026 Joseph Wander.

---

## Contact

Joseph Wander
- GitHub: [github.com/AIWander](https://github.com/AIWander/)
- Email: [josephwander@gmail.com](mailto:josephwander@gmail.com)
