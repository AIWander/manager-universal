# Example: Parallel Workflow with Dependencies

Execute multiple tasks with dependency gates using `task_run_parallel`.

## Scenario

Rewriting an auth module: implement, test, add backward compat, then
integration test. Some steps can run in parallel, others depend on earlier
steps completing first.

## Define the DAG

```
# Create a loaf for durable coordination
loaf = create_loaf(
  name="Auth Module Rewrite",
  goal="Replace session-token auth with JWT, maintain backward compat"
)

# Submit the DAG
task_run_parallel(
  loaf_id=loaf.id,
  tasks=[
    {
      id: "jwt_impl",
      prompt: "Implement JWT auth middleware in auth/jwt.py. \
        HS256, extract user_id and roles, 401 on invalid/expired.",
      backend: "claude_code"
    },
    {
      id: "migration",
      prompt: "Write DB migration for jwt_secrets table. \
        Columns: id, secret_key, created_at, rotated_at.",
      backend: "codex"
    },
    {
      id: "jwt_tests",
      prompt: "Write pytest suite for JWT auth middleware. \
        Cover: valid token, expired, malformed, missing header, role extraction.",
      backend: "codex",
      depends_on: ["jwt_impl"]
    },
    {
      id: "compat",
      prompt: "Add backward-compat shim: if Authorization header contains \
        a session token (not JWT), translate to JWT internally.",
      backend: "claude_code",
      depends_on: ["jwt_impl", "migration"]
    },
    {
      id: "docs",
      prompt: "Update API docs to reflect JWT auth. Include migration guide.",
      backend: "gemini",
      depends_on: ["compat"]
    }
  ]
)
```

## Execution order

1. `jwt_impl` and `migration` run **in parallel** (no dependencies)
2. `jwt_tests` starts when `jwt_impl` completes
3. `compat` starts when both `jwt_impl` and `migration` complete
4. `docs` starts when `compat` completes

## Wait and finalize

```
# Block until everything finishes
task_watch(task_ids=[...all task ids...], timeout=900)

# Review results
task_explain(task_id="jwt_impl")
task_explain(task_id="jwt_tests")
task_explain(task_id="compat")

# Close the loaf
loaf_close(
  loaf_id=loaf.id,
  summary="JWT auth deployed with backward compat. \
    5 tasks completed. Full test coverage."
)
```

## If a task fails mid-DAG

Downstream tasks that depend on the failed task will not start.
Independent branches continue.

```
# Check what happened
task_explain(task_id="jwt_tests")

# Rollback if needed
task_rollback(task_id="jwt_tests")

# Retry with context
task_retry(
  task_id="jwt_tests",
  additional_context="Install pytest-asyncio first: pip install pytest-asyncio"
)

# Re-watch
task_watch(task_ids=["jwt_tests"])
```
