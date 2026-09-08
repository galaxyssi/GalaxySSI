# Desktop Execution Write Fencing

## Implemented Boundary

The task manager's in-memory execution key is necessary but not sufficient for
multiple processes. A recovering manager can advance the committed generation
while an old manager still holds generation 1 in memory. The task store now
compares a private `_storage_revision` inside the same SQLite write transaction
that persists the task and its result chunks.

- A new record starts at revision 1. A successful write returns the next revision.
- Updates must present the revision they read. Two processes using the same
  revision cannot both commit, including updates within the same generation.
- App, client conversation, client turn, task and source message identity cannot
  change on an existing task. Legacy conversation fallback remains deterministic.
- Execution generation cannot decrease. Status sequence cannot decrease within
  a generation. Storage revision is independent of status sequence because trace
  and checkpoint writes do not always produce a new visible status event.
- Comparison, task write, output-chunk replacement and the Run event append are
  committed or rolled back together when called by the task manager.
- A rejected manager reloads committed data, marks its local task writer fenced,
  suppresses subsequent mutations/snapshots and wakes its bounded worker wait.
  Merely reading the winning record does not grant it permission to write again.
- Internal revision/fenced fields are not included in App task notifications.
- Dispatch, status completion, heartbeats and progress watchdogs stop when they
  discover a durable ownership conflict. A lost writer does not convert the
  winning execution into a failed task or emit its stale result as a fallback.

Existing records without `_storage_revision` are treated as revision 0 for the
first guarded update. No database, pairing or chat reset is required. All writers
must use this implementation; arbitrary SQL writers and old binaries that bypass
the guard are outside this protection.

## Verification

The focused suite covers two independent SQLite connections, two actual Python
writer processes, and a still-running old task-manager process after a second
manager restores generation 2. It also covers identity mismatches, regressing
generation/status sequence, chunk preservation, transaction rollback, existing
records without a revision, lost-writer retry rejection and public-field privacy.

Twelve focused tests and nine subtests passed. The expanded task/callback suite
passed 240 tests and 155 subtests in 46.41 seconds, including the focused suite;
these overlapping counts must not be added as unique coverage. Desktop's 29 Node
checks, structure checks, repository checks and `git diff --check` also passed.

### Real S20U Delivery

Desktop 1.1.21 ran against the existing S20U (SM-G9880) Android 1.1.12 (898)
installation. No App uninstall, pairing reset or encryption bypass was performed.
This Desktop-only change does not claim that the phone has the newer Android
knowledge-store changes from main installed.

The explicit live instrumentation test
`AgentDeliveryLiveDeviceTest#textAndImageReachTheConfiguredDesktop` used concurrency
2 and reused each conversation for a subsequent image turn. All four requests
completed over the real encrypted MQTT/model/App path in a 31-second test run.
The image check requires the complete `2 + 2 = 4` equation, not merely a marker.

| Source message | Kind | Elapsed | Execution generation |
| --- | --- | --- | --- |
| 1788899938980 | Text | 14,310 ms | 1 |
| 1788899938981 | Text | 16,532 ms | 1 |
| 1788899938982 | Image | 13,320 ms | 1 |
| 1788899938983 | Image | 12,074 ms | 1 |

Each request had a distinct task and turn, with two conversation IDs reused
across text/image turns. The backend subsequently reported all four tasks as
completed, with zero active/pending tasks in both normal and control pools.
Only S20U was operated. Local ignored evidence is in
`build/s20u-ownership-lifecycle-live.log` and
`build/s20u-ownership-lifecycle-device.log`.

The implementation was rebased by fast-forward onto main `cc5d707f8` before
submission. The final upstream delta only changed CI compiler-memory settings.

## Multi-Node Work Still Required

This is a durable write fence, not a distributed scheduler or an execution lease.
SQLite WAL is local coordinator storage; do not put it on a network share for
workers to write directly. A multi-host deployment needs an authenticated worker
protocol whose coordinator alone owns this database.

The next boundary must include worker identity plus process incarnation, bounded
capacity advertisements, durable lease epochs and deadlines, conditional renewal,
revocation, ordered progress receipts and fenced result acceptance. Reassignment
must advance ownership before dispatch. Lost/expired workers must stop dispatching
new tool calls, and side-effecting calls need their own idempotency/receipt policy.

Deletion/recreation of the same task ID also needs an ownership incarnation or
tombstone to prevent ABA reuse; a per-record revision alone is not an eternal
identity. Neither database fencing nor a lease makes arbitrary external effects
exactly once. Single-node 10,000-pending-job tests are not proof of 10,000 concurrent
model processes or of physical multi-node failover.

This follow-up is separate from merged PR 2915 so that delivery/fair-queue changes
remain independently reviewable while ownership work continues.
