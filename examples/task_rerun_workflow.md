# Example: task_rerun Workflow (v1.1.1)

`task_rerun` re-submits a completed task with modifications. It reuses the
original prompt instead of writing a new one from scratch.

## When to use task_rerun vs task_retry

| Situation | Tool |
|-----------|------|
| Task **failed** — need to fix and re-run | `task_retry` (auto-injects error) |
| Task **completed** but needs another pass | `task_rerun` (reuses original prompt) |

## Basic rerun with additional context

The original task produced good code but missed edge cases:

```
task_rerun(
  task_id="task_abc123",
  additional_context="Also handle the case where input is an empty array \
    and the case where input contains null values"
)
```

The backend receives the original prompt + your additional context appended.

## Rerun with file injection

Inject files the backend should read during the re-run:

```
task_rerun(
  task_id="task_abc123",
  additional_context="Use the edge case patterns from the test file",
  include_files=["tests/edge_cases.py", "docs/validation_spec.md"]
)
```

## Rerun on a different backend

The original ran on Codex but needs Claude Code's multi-tool capability:

```
task_rerun(
  task_id="task_abc123",
  backend_override="claude_code",
  additional_context="This needs multi-file changes — update both the \
    implementation and the test suite"
)
```

## Task lineage

The new task automatically gets:
- `rerun_of`: points to `"task_abc123"` (the original)
- `parent_task_id`: set to `"task_abc123"`

Query `task_status` on the new task to see these fields. This lets you
trace the history of iterative refinement.

## Full workflow

```
# 1. Submit original task
original = task_submit(
  prompt="Write a CSV parser for sales_data.csv with type coercion",
  backend="codex",
  wait=true
)

# 2. Review output — mostly good but floats are truncated
# 3. Rerun with fix guidance
fixed = task_rerun(
  task_id=original.task_id,
  additional_context="Preserve full float precision — do not truncate \
    to 2 decimal places. Use Decimal type for currency fields."
)

# 4. Wait for the rerun
task_watch(task_ids=[fixed.task_id])

# 5. Check lineage
status = task_status(task_id=fixed.task_id)
# status.parent_task_id == original.task_id
# status.health == "done"
```
