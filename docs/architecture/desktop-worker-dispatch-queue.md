# Durable Worker Dispatch Queue

Desktop 1.1.25 adds a coordinator-local dispatch queue on the existing Run SQLite
database. This is a step toward multi-node execution, not a claim that the remote
worker execution protocol or automatic model routing is complete.

## Admission And Ownership

- A trusted coordinator admits a new, validated, undispatched `queued` task.
- Admission specifies a provider and an explicit allowlist of enrolled workers.
  Pairing alone never authorizes a peer to receive work or private task context.
- Desktop 1.1.34 also snapshots each target's full enrollment pairing binding in
  the admission transaction. Reusing a worker ID after re-pairing cannot grant the
  new identity access to previously queued requests. Ordinary reconnects with
  the same pairing remain eligible; one changed target does not block another
  original authorized target.
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
   fairness, then admission FIFO, among the worker's offered providers. The
   target's admission-time pairing binding must match its authenticated current
   enrollment, not merely its worker ID.
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

- MQTT poll/renew/progress/result schemas and allowlisted projection construction
  are implemented in Desktop 1.1.26; see `../protocol/worker-control-v1.md`.
  The explicit controller added in 1.1.31-1.1.33 connects worker execution and
  committed-receipt recovery; normal-App queue admission remains unconnected.
- Artifact transfer and physical multi-host acceptance of the bounded worker
  client, monotonic lease deadlines and isolated workspace/tool policy.
- Original-App status/result notifications are committed with remote receipts in
  1.1.26 and drained by the existing MQTT retry thread. Real network/worker
  delivery and artifact integration still require acceptance testing.
- Explicit remote cancellation, interruption recovery and safe reassignment.
  Expiry alone must not cause duplicate external side effects.
- Real broker, two-node and physical-App end-to-end tests, including images,
  disconnects, restarts and actual concurrent provider saturation.

The 1.1.26 authenticated MQTT adapter calls this module. No automatic offload,
enrollment UI or new worker process is enabled. Ordinary Android/Desktop routing remains local
unless a future authenticated coordinator integration explicitly admits work.

## Target Identity Upgrade, Desktop 1.1.34

Investigation of ordinary-App offload prerequisites reproduced a disclosure bug:
a re-paired node with the same worker ID could poll a private request admitted
for its previous identity. Admission now saves the full pairing binding per
target and poll selection matches it inside the grant transaction. The binding
includes route, Signal identity, both fingerprints, link secret and access grant.
It is private coordinator metadata, not a new wire field or public task field.

Exact duplicate admission does not refresh authorization. A request intentionally
authorized for a new identity needs fresh trusted admission under a new task ID;
it must not mutate the old task's identity or replay previously dispatched work.
Legacy target rows without a saved binding remain in the queue but are ineligible
for new dispatch. Migration does not guess their original authorization from the
current enrollment, delete tasks or start a model. These retained rows still count
toward the queue budget; operator reconciliation remains necessary.

The targeted regression covers re-pairing, changed binding components, same-pair
reconnect, duplicate admission, unaffected alternate targets and legacy schema
upgrade. This is a prerequisite for safe ordinary-App routing, not proof that
automatic offload or phone/multi-host acceptance is finished.

### Target Binding Verification, September 9, 2026

- Before the fix, both re-pair disclosure regressions failed by returning an old
  task grant to the newly paired identity; same-pair reconnect already passed.
- After the fix, the focused target/queue/protocol suite passed 46 tests and 37
  subtests in 147.67 seconds. Final expanded task/worker/MQTT/process regression
  passed 635 tests and 317 subtests, with three opt-in live cases skipped, in
  182.83 seconds. Counts overlap and are not additive.
- The real Codex text/native-PNG controller case was explicitly enabled and
  passed in 15.70 seconds, making two actual model calls and recovering a dropped
  terminal acknowledgement. Coordinator and transport remained local fixtures.
- Root repository checks, 29 Desktop Node tests, structure and diff checks passed.
  Upstream was synchronized through `02477c4f0`; PR #2933 was already merged.
  Desktop package and lock metadata is 1.1.34. No Android code was changed by
  this fix and no APK or Desktop runtime was replaced.
- Read-only device verification still reported S20U Android 1.1.18 (904), last
  updated at 11:39:01. Desktop health remained ready with ten active MQTT
  subscriptions. These checks are not phone-origin model delivery acceptance.

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
