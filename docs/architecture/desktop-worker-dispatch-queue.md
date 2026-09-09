# Durable Worker Dispatch Queue

Desktop 1.1.25 adds a coordinator-local dispatch queue on the existing Run SQLite
database. This is a step toward multi-node execution, not a claim that the remote
worker execution protocol or automatic model routing is complete.

## Admission And Ownership

- A trusted coordinator admits a new, validated, undispatched `queued` task.
- Admission specifies a provider and an explicit allowlist of enrolled workers.
  Pairing alone never authorizes a peer to receive work or private task context.
- The complete App/conversation/turn/task/generation key is preserved, along with
  the original source message and contact. An existing local task cannot be
  moved into the queue by overwriting it.
- Task state, Run event, target allowlist and queue reservation commit together.
  Retrying identical admission is a no-op; reusing its task ID with changed data
  is rejected.
- Queue reservations fence ordinary task writers before a lease exists. A local
  manager restart observes the task without changing its generation or starting
  a provider. Reservation tombstones also prevent reuse after history deletion.
- The default queue bound is 10,000 waiting tasks. Waiting tasks create neither
  threads nor provider processes. This is not 10,000 simultaneous model calls.

## Atomic Poll

One transaction performs all of the following:

1. Verify the paired source, enrollment binding, incarnation, session epoch and
   recent heartbeat.
2. Replay the latest matching poll receipt, or require its next sequence number.
   An empty reply is also a receipt; a later poll must use a new sequence.
3. Bound capacity by both the operator limit minus outstanding worker leases and
   advertised free slots minus grants since that heartbeat. Leases originating
   outside this queue also count. An expired or revoked nonterminal lease does
   not prove its process stopped and does not silently release capacity.
4. Select an authorized task using persisted App fairness, then conversation
   fairness, then admission FIFO, among the worker's offered providers.
5. Grant the full execution key and private lease capability, persist the
   dispatch checkpoint and running task projection, advance fairness, and store
   the poll receipt.

Only after commit may an adapter transmit the dispatch. `running` at this point
means the dispatch was committed, not that an external tool already ran.
Repeated delivery still requires worker-side deduplication by execution key and
lease epoch. One receipt row per enrolled worker bounds poll-receipt storage.
Retries of expired or finished grants are rejected, not replaced with new work.

The returned internal dispatch contains private task context. It is not a public
App event and must not be serialized wholesale into MQTT messages or UI logs.

## Results And Storage

The internal `apply_task` accepts a coordinator-built projection using the
existing ordered lease receipt mechanism. Run event, task revision, chunked
output and terminal capacity release are transactional. A failed write cannot
release a worker slot or acknowledge a partially persisted result. Completed
dispatches cannot return to running. Exact latest receipt retries are no-ops.
The original source message, contact, agent, prompt, request snapshot, input
attachments and execution policy cannot be replaced by a worker projection.

The task store supports caller-owned transactions. Its single-task read now
holds one read snapshot across metadata and output chunks; concurrent writers
cannot make a reader combine old metadata with new chunks. Shared transactions
must be active and belong to the same database. Callers must propagate failures
or roll back, and keep admission batches small enough not to starve heartbeats.

## Verification And Remaining Integration

`test_agent_worker_queue.py` covers admission retries, ownership before claim,
App/conversation fairness across coordinator recreation, same-conversation
interleaved turns, explicit targets/providers, capacity bounds, stale sessions,
rollback, chunk-read consistency, and 10,000 actual queued database records.
It also launches separate coordinator processes to test same-poll replay and
two authenticated worker identities racing for one task with exactly one winner.
These are same-host SQLite tests, not a multi-host or real-model benchmark.

Still required before enabling remote execution for normal App requests:

- MQTT poll/renew/progress/result schemas and strict allowlisted projection
  construction, with pairing and session authorization at each operation.
- A real worker client with bounded execution, monotonic lease deadlines,
  execution deduplication, isolated workspace/tool policy and artifact transfer.
- Original-App status/result delivery from committed remote receipts, without
  leaking private worker capabilities or accepting stale execution events.
- Explicit remote cancellation, interruption recovery and safe reassignment.
  Expiry alone must not cause duplicate external side effects.
- Real broker, two-node and physical-App end-to-end tests, including images,
  disconnects, restarts and actual concurrent provider saturation.

No MQTT polling endpoint, automatic offload, enrollment UI or new worker process
is enabled by this queue module. Ordinary Android/Desktop routing remains local
unless a future authenticated coordinator integration explicitly admits work.

## September 9, 2026 Validation

- Expanded Python regression: 336 tests and 205 subtests passed in 106.83 seconds.
  This run included 22 queue tests before the last two scenarios were added.
- Final queue suite: 24 tests and 17 subtests passed in 22.79 seconds, including
  the final request-context guards. These tests overlap the expanded suite;
  their counts must not be added together.
- The final 10,000-record queue test took 19.85 seconds on the development host.
  Records were admitted in batches of 100. This measures fixture admission and
  queue assertions, not model latency, throughput or a network benchmark.
- Repository `npm run check` passed. Desktop `npm run check` passed all 29 Node
  tests and its structural check.
- Desktop was normally closed only after both work pools were idle, then started
  from the 1.1.25 checkout. Post-run health: ready, encrypted bridge ready, MQTT
  connected, 10/10 subscriptions active, zero active/pending tasks in both pools.
- Only S20U (`SM-G9880`) was operated. Android remained 1.1.12 (898); this change
  contains no Android production changes or new APK. Pairing/history were kept.
- The opt-in real-model instrumentation test passed in 25.368 seconds. Two
  concurrent private fixture conversations each sent a text turn then a PNG
  image turn. Four of four replies matched contact, source, conversation, turn,
  task, success and generation 1. Image replies had to contain the entire
  `2 + 2 = 4` equation and their unique marker.

| Request | Source message | Turn latency | Generation |
| --- | --- | --- | --- |
| Conversation A text | 1788913061464 | 11,791 ms | 1 |
| Conversation B text | 1788913061465 | 12,500 ms | 1 |
| Conversation A image | 1788913061466 | 10,957 ms | 1 |
| Conversation B image | 1788913061467 | 9,578 ms | 1 |

Ignored local evidence: `build/s20u-worker-dispatch-queue-live.log` and
`build/s20u-worker-dispatch-queue-device.log`. This device run verifies the
ordinary single-node App path after storage changes. It does not verify remote
worker dispatch, multiple physical Apps, simultaneous turns in one real-model
conversation, or ten simultaneous provider executions.
