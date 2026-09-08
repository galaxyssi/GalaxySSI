# Desktop Worker Lease Boundary

## Status

`AgentWorkerLeaseLedger` is coordinator-side storage for a future authenticated
worker adapter. It uses the existing local Run SQLite database, not a shared
network drive. This change does not create a network endpoint, enroll workers,
or automatically dispatch existing Desktop tasks to another computer.

The lease records bind App, conversation, turn, task, execution generation,
worker ID, worker process incarnation, lease epoch and a random 256-bit bearer
capability. Capability tokens are private coordinator state and must never be
copied into public task snapshots, logs, model prompts or MQTT topics. Worker
identity/incarnation arguments must come from an authenticated connection, not
from an untrusted message body.

## Implemented Invariants

- Claims serialize in a SQLite writer transaction. A competing claim must present
  the last observed epoch and cannot steal a live lease, even after the same worker
  restarts under a different process incarnation.
- Claim retries use a claim ID. An exact replay returns the original grant without
  extending its expiry; changed parameters are rejected. Replaying an expired
  grant does not authorize work because renewal/result acceptance rechecks expiry.
- Reassignment after expiry or revocation requires a strictly newer execution
  generation and increments the persistent lease epoch. Scope and epochs remain
  retained after revocation, preventing task-ID reuse from resetting this boundary.
- An existing completed task or already dispatched local execution cannot be
  newly leased. Queued local tasks can be explicitly delegated by the coordinator.
- Renewals and result writes require the matching worker, incarnation, epoch,
  capability and complete execution key, and reject expired/revoked grants.
- Result receipts are sequential. An exact retry of the latest receipt is a no-op;
  reordered receipts or reuse with different content are rejected.
- Task persistence, output chunks, the Run event and receipt advancement commit
  together. A failed task revision check rolls back the event and receipt too.
- Ordinary `AgentTaskStore.upsert()` callers cannot bypass an existing worker
  lease. Unleased local tasks keep their existing path. Lease validation runs
  inside the same writer transaction as the existing revision comparison.

`apply_task()` accepts a coordinator-built task projection, not arbitrary remote
task fields or remote SQL. Network adapters will need an allowlist when mapping
worker progress/output onto that projection. Callers must not hold a SQLite
transaction across model execution, network I/O or tool execution.

## Verification

The focused tests cover claim replay, four competing actual Python processes,
coordinator reconstruction, renewal, deadline boundaries, revocation, generation
advancement, all capability components, ordered receipts, changed result scope,
atomic task/Run rollback, existing local work and the ordinary-writer bypass.
These are coordinator/storage tests, not physical multi-host acceptance.

On 2026-09-09, the focused suite passed 15 tests and 12 subtests. The expanded
task/recovery suite passed 255 tests and 167 subtests in 77.69 seconds (including
the focused suite, not additional unique coverage). Desktop's 29 Node checks,
structure check, repository checks and diff whitespace check passed.

Desktop 1.1.22 was then started against the existing S20U SM-G9880 Android
1.1.12 (898). No App reinstall/reset was performed. The explicit live delivery
instrumentation used two conversations, each with a text turn followed by an image
turn, and passed all four real MQTT/model/App requests in 32.31 seconds. Text
requests took 12,300/13,429 ms; image requests took 14,896/16,591 ms. Each response
matched its task/turn/conversation and execution generation 1; images additionally
required recognition of the full generated equation. Both task pools were idle
after completion. Evidence remains local and ignored in
`build/s20u-worker-lease-guard-live.log` and
`build/s20u-worker-lease-guard-device.log`.

This live test verifies that introducing the storage guard does not block the
existing unleased single-node path. It does not exercise a remote worker lease.

## Remaining Integration

1. Authenticate/enroll worker nodes and bind permissions, identity and process
   incarnation. Never trust a worker ID supplied only in a JSON body.
2. Connect worker availability/capacity to the App/conversation fair scheduler,
   using durable pending dispatch and bounded network requests instead of one
   waiting thread per queued task.
3. Add a coordinator recovery path for leased tasks. The ordinary local manager
   must not adopt them as new local executions; its writes are deliberately fenced.
4. Add worker-side monotonic deadlines and cancellation checks before new tool
   calls. The current coordinator deadline uses its wall clock; clock regression,
   coordinator host replacement and revoked-worker side effects need explicit
   fail-closed handling before enabling automatic remote dispatch.
5. Handle all receipt replay windows, capacity advertisements, attachment access,
   per-worker quotas, lease cleanup and credential revocation. Only the latest
   accepted result receipt is currently replayable.
6. Validate two independent nodes with disconnect, coordinator restart, worker
   process death, result retry and stale side-effect attempts, then run real model
   and real App multi-node tests.

The current running single-node Desktop must not be described as having complete
multi-node scheduling or exactly-once external side effects because this storage
boundary has passed tests. Keep remote dispatch disabled until those integrations
and failure tests are present.
