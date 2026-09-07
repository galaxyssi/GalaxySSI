# Campaign operation ownership

Desktop 1.0.45 serializes dispatch, revision, and control for each durable
evolution campaign across executor instances and processes. It uses the existing
nonblocking OS-lock implementation, with a stable hashed campaign key and a
retained lock file under the shared evolution store.

## Failure addressed

A node claim was durable, but its task creation happened outside any cross-process
campaign lock. While one executor was materializing the claimed child, another
executor could observe the running reservation without a child and enter the same
creation path. Per-manager Python locks could not prevent this. Control/revision
could also race dispatch between graph observation and child creation.

The regression test reproduced this before the fix: a second executor entered
dispatch while the first was deliberately held inside child materialization.

## Boundary

- Ownership spans one campaign tick, revision, or control operation, including
  its task creation/start callbacks. It is not held for the lifetime of a child.
- Another executor returns `campaign_operation_busy` without mutating the plan.
  The API reports HTTP 409 with this retryable code; scheduled ticks report a busy
  observation rather than a failed campaign and can continue to other campaigns.
- Read-only get/list remain available. Independent campaigns can advance through
  the same executor concurrently; the old global Python campaign lock is removed.
- The existing task ownership, process termination evidence, and worker-capacity
  checks remain in place for actual child execution.
- A process crash releases the OS lock. The next executor reads the persisted DAG
  reservation and child record, preserving the deterministic child identity.
- There is no lease expiry that can steal a still-live operation and no additional
  limit on task count, plan revisions, or total campaign duration.

## Validation

Tests cover concurrent executors, pause/revision exclusion, nonblocking read-only
views, independent plans on one executor, retry after failure, scheduled busy
observations, and the API error contract.

A real subprocess test uses the production EvolutionManager and stores. It exits
with `os._exit(23)` after the child task and metadata have been persisted but before
dispatch returns. A new manager resumes the exact child, creates no duplicate task,
and leaves the dependent node pending. Only the child-start callback is replaced
with a deterministic state transition; this test does not invoke a real provider,
run repository gates, publish a PR, or prove full campaign completion.

## Remaining work

These are same-host ownership guarantees on a shared state store, not distributed
leases across different hosts. The legacy non-ledger campaign adapter is unchanged.
Full real-provider DAG replanning, merged-PR dependency execution, resource-level
write concurrency, and long-duration/device-reboot acceptance remain separate
requirements of the overall goal.
