# Changelog

All notable changes to manager-universal are documented here.

## [1.0.1] - 2026-04-29

### Fixed

- **Dashboard port pin honored on first attempt.** v1.0.0 inherited a public-v1.4.0 bug
  where the dashboard port resolution applied a random jitter (0..19) to the user-pinned
  `CPC_DASHBOARD_PORT` *before* the first bind attempt. With `CPC_DASHBOARD_PORT=9999`,
  the dashboard would land somewhere in 9999..10018 chosen randomly per restart, breaking
  bookmarked URLs. Fixed by binding to the preferred port directly on first attempt;
  walk-forward through the 100-port range still kicks in only on collision.

## [1.0.0] - 2026-04-29

Initial public release of **manager-universal** -- the universal-portability
distribution of [manager](https://github.com/AIWander/manager).

### Reliability fixes (not in main manager repo)

#### Retry budget
- `max_retries` defaults to 1 (was unlimited). When a task exhausts its
  retry budget it transitions to `failed_max_retries` and stops auto-retrying.
- Retry budget inherited by retry tasks so escalation chains stay bounded.
- New `FailedMaxRetries` task status added to distinguish budget-exhaustion
  from transient failures.

#### Destructive-task stall safety
- New `stall_recovery` field on every task: `auto` (default) or `manual`.
- Prompts containing destructive keywords (`git push`, `cargo build`,
  `docker push`, `terraform apply`, etc.) default to `stall_recovery: manual`.
- `manual` stall: task pauses on dead-process detection, fires a toast
  notification, and waits for `manager:resume_task` -- no auto-retry.
- `auto` stall: task transitions to `failed` and retries (up to `max_retries`).
- Explicit `stall_recovery` param in `submit_task` overrides the heuristic.

#### PID-liveness stall watchdog
- Replaced time-based output-silence detection with direct child-process
  liveness checks via `sysinfo`.
- Only kills tasks whose child process is confirmed dead -- eliminates false
  positives on slow tools (cargo builds, large test suites).
- `stall_recovery: auto` -> marks task `Failed("orphaned-pid-dead")` + queues retry.
- `stall_recovery: manual` -> marks task `Paused(StallManualRecovery)` + toast.

#### Retry backoff
- Fixed retry backoff to 720 s (12 minutes) before retrying a dead-process
  task. Previous behavior retried immediately, which typically just re-stalled.
- 12-minute window gives CI, build pipelines, and model-inference services
  time to settle before a new attempt fires.

### Cherry-picks from main repo (v1.3.5-v1.4.5)

1. **JSON-RPC notification envelope fix** -- silences Claude Desktop Zod
   validation errors on notification messages.
2. **Dashboard port bind retry** -- retries 100 ports with random jitter
   if the default port (9218) is busy.
3. **Embedded-only dashboard** -- dashboard HTML served from compiled-in
   bytes only; stale disk files no longer override.
4. **Codex `--` separator** -- defensive `--` added on all 6 arg-building
   sites to prevent prompt content from being parsed as flags.
5. **Recovery notify async** -- recovery notifications run in a background
   thread; no longer blocks MCP server initialization.
6. **Restart recovery persists status** -- recovery state written to disk
   on restart; eliminates notification storm on repeated restarts.
7. **Per-reason notification icons** -- `[Error]` / `[Warning]` / `[Info]`
   prefix icons on toast notifications.
8. **Notification label scoped to Done** -- custom `notification_label`
   override only applies to task-complete notifications.
9. **LOAFS panel fix** -- fallback to active breadcrumb count when no
   LOAFS data is present.
10. **COMPLETED TODAY panel fix** -- data source wired correctly; panel
    now shows today's completions.

### Universal portability

- Zero hardcoded user paths. All paths resolve via env vars or platform
  defaults (see README for full env var table).
- `CPC_WORKSPACE_ROOT` replaces hardcoded workspace roots.
- `CPC_VOLUMES_PATH` resolves via `cpc-paths` crate (env -> config file ->
  auto-detect -> error).
- `USERPROFILE` used for user-home path (set by Windows; override for testing).

### Dual-source breadcrumb reading

- Reads breadcrumb state from two directories:
  - `OPS_BREADCRUMBS_DIR` (default: `%LOCALAPPDATA%\CPC\ops-data\logs`)
  - `LOCAL_BREADCRUMBS_DIR` (default: `%LOCALAPPDATA%\CPC\local-data\logs`)
- Entries deduped by `id` field; local source wins on conflict.
- Falls back gracefully when either directory is absent.

### Other

- Dashboard URL written to `%LOCALAPPDATA%\manager-mcp\dashboard_url.txt`
  on startup.
- Dashboard port default changed to 9218.
- `manager:reconnect_orphans` reconnects tasks whose child processes
  survived a manager restart.
