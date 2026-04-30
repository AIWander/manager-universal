# Example: Health Enum Interpretation (v1.1.1)

The `health` field on `task_status` replaces `stall_detected` as the
authoritative field for behavior decisions.

## The 9 health values

| Value | What it means | What to do |
|-------|--------------|------------|
| `done` | Task completed successfully | Read output, extract insights |
| `failed` | Task failed | Check error, `task_rollback`, then `task_retry` |
| `queued` | Waiting to be picked up by a backend | Wait — backend may be busy |
| `cancelled` | Cancelled by user or system | Resubmit if still needed |
| `paused` | Paused by user | Resume when ready |
| `running_long_tool` | Backend tool is mid-flight | **Keep waiting.** Do not cancel. |
| `stalled` | No activity beyond 90s threshold, no tool running | Investigate — may need cancel + retry |
| `idle` | Session is open but no active work | Send next instruction or close session |
| `running` | Normal execution in progress | Wait normally |

## The critical distinction: `running_long_tool` vs `stalled`

Before v1.1.1, both states showed as `stall_detected: true`. Now they're
separate:

**`running_long_tool`** — A backend tool (Write, Edit, Bash, etc.) has a
`"started"` event with no completion event yet. The backend is working.
This is normal for large file operations. A Write on a 12KB file can take
90+ seconds between visible step updates.

**`stalled`** — No tool is mid-flight AND no activity for 90+ seconds.
The backend may actually be stuck.

## Reading health in practice

```
status = task_status(task_id="task_abc123")

if status.health == "done":
    output = task_output(task_id="task_abc123")
    # Process result

elif status.health == "failed":
    task_rollback(task_id="task_abc123")
    task_retry(task_id="task_abc123",
      additional_context="Error context here")

elif status.health == "running_long_tool":
    # A tool is mid-flight. DO NOT cancel.
    # active_tool_running will be true.
    # Just wait — use task_watch for blocking.
    task_watch(task_ids=["task_abc123"], timeout=600)

elif status.health == "stalled":
    # Actually stuck. No tool running.
    # Consider cancelling and retrying.
    task_cancel(task_id="task_abc123")
    task_retry(task_id="task_abc123",
      additional_context="Previous attempt stalled")

elif status.health == "running":
    # Normal execution. Wait.
    task_watch(task_ids=["task_abc123"])
```

## The `active_tool_running` field

Boolean companion to `health`:

```
status = task_status(task_id="task_abc123")
status.active_tool_running  # true = a tool is mid-flight
```

The stall detector uses this internally: when `active_tool_running` is
`true`, the detector skips entirely. You can also use it directly if you
want finer-grained monitoring.

## Migration from `stall_detected`

`stall_detected` still exists for backward compatibility. But:

| Old pattern | New pattern |
|------------|------------|
| `if stall_detected: cancel` | `if health == "stalled": cancel` |
| `if stall_detected: wait more` | `if health == "running_long_tool": wait` |

The old boolean couldn't distinguish these cases. The new enum can.
