# Example: Delegate a Coding Task

Single-task delegation — the simplest manager pattern.

## Scenario

You need input validation added to a function. It's ~40 lines of work,
above the 33-line threshold. Delegate it.

## Short task with `wait=true`

For tasks under ~5 minutes, use `wait=true` for synchronous execution:

```
result = task_submit(
  prompt="Add input validation to user_create() in api/users.py. \
    Validate email format with regex, password length >= 12 chars, \
    and username must be alphanumeric 3-30 chars. Return 422 with \
    specific error messages for each validation failure.",
  backend="codex",
  working_dir="C:/project",
  wait=true
)
```

The call blocks until Codex finishes. Result is immediately available.

## Longer task with fire-and-forget

For tasks that may take several minutes:

```
result = task_submit(
  prompt="Refactor the auth module to use JWT. Update middleware, \
    session handling, and all route guards.",
  backend="claude_code",
  working_dir="C:/project"
)
# Returns immediately with result.task_id

# Do other work while the backend runs...

# When ready, block until complete:
task_watch(task_ids=[result.task_id], timeout=600)

# Get the full output:
output = task_output(task_id=result.task_id)
```

## After delegation

1. Review the output for correctness
2. Scan for extraction-worthy content (corrections, decisions, discoveries)
3. If the task failed: `task_rollback` then `task_retry` with context

## Choosing a backend

| Task shape | Backend |
|-----------|---------|
| Write a function, create a script | `codex` |
| Multi-file refactor, needs tool access | `claude_code` |
| Analyze a log, summarize docs | `gemini` |
| Classify errors, generate decision matrix | `gpt` |
| Not sure | `auto_route` (recommended default) |
