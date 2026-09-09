# Paired Worker Control v1

Status: enrollment, connection, heartbeat, poll, renewal, structured report,
read-only terminal receipt lookup and bounded paired RPC response correlation
implemented. Explicit headless worker controllers are connected; automatic
normal-App offload is not yet connected. No existing pair is enrolled
automatically, including pairs with full Desktop Executor access.

## Transport And Authorization

Use the existing paired Link MQTT topics, wire sealing and Signal encryption.
Worker controls are routed only after the incoming topic, cryptographic sender,
application sender and envelope have passed the existing pairing validation.
There is no global worker MQTT topic or new network listener.

A Desktop operator explicitly enrolls a current paired route through
`PUT /api/agent/workers/{route}` with `worker_id`, `max_parallel` (1..128) and a
nonempty `providers` list (at most 32 provider IDs). This API requires both a
loopback caller and the existing `x-galaxyssi-token` Desktop API credential.
`GET` reads that route's authorization/session state; `DELETE` revokes enrollment.
Revocation remains possible after the original pair has been removed.

The enrollment binds the route, Signal name, both identity fingerprints, Link
secret and pairing access grant. Re-pairing or grant changes require explicit
operator re-enrollment. MQTT requests cannot enroll themselves. Worker IDs in
payloads are not identity selectors: the authenticated paired route determines
which enrolled worker is allowed to act.

## Requests

Every request uses protocol `galaxyssi.worker-control.v1`, a bounded `request_id`
and a unique transport envelope message ID. Application retries use a new envelope
ID with the original logical request parameters. The Desktop RPC client also
generates a fresh `attempt_id` for each transport attempt; this does not advance
connect, heartbeat, poll or report sequences. A transport delivery ACK confirms
transport acceptance, not successful worker enrollment or execution.

1. `agent_worker_status`: read only the caller's authorization and session epoch.
2. `agent_worker_connect`: provide a new process `incarnation`, the observed
   `expected_session_epoch`, and offered `providers` (a subset of the enrollment).
   The coordinator advances the epoch and initially advertises zero free slots.
   Exact replay of the same connect request does not advance the epoch again.
3. `agent_worker_heartbeat`: provide `incarnation`, `session_epoch`, a positive
   monotonically increasing `sequence`, and `available_slots` within the operator's
   configured maximum. Exact replay does not refresh liveness; reordered/changed
   receipt sequences are rejected. Gaps are allowed because only current capacity
   matters, unlike ordered task result events.
4. `agent_worker_poll`: provide the current incarnation/session and a positive
   `sequence` starting at 1 for each worker session. Poll sequences are separate
   from heartbeat and per-task report sequences. Only the next sequence or an
   exact latest retry is accepted. The response contains `job: null` or the
   authorized job and lease. Even an empty reply consumes a sequence.
5. `agent_worker_renew`: provide the current incarnation/session and the complete
   lease from the grant. Only a current, unexpired, nonterminal execution can be
   renewed. The response returns the lease and coordinator `server_time_ms`.
6. `agent_worker_report`: provide the current incarnation/session, complete lease,
   per-lease ordered `sequence` starting at 1, and the exact `report` fields below.
   The coordinator constructs the task projection from its own committed record.
7. `agent_worker_receipt` (Desktop 1.1.32): read only an already committed terminal
   receipt. Provide the original `incarnation`, complete `lease`, report `sequence`
   and `report_digest` (SHA-256 of compact, sorted-key UTF-8 JSON of the original
   normalized report). The authenticated route must still be enrolled with the
   same pairing binding. Original App/conversation/turn/task/generation, lease
   epoch, token, owner and digest must all match. An expired heartbeat/lease or
   newer worker session does not prevent this read; revoked enrollment does.
   Returns `receipt: null` when there is no committed terminal receipt, otherwise
   `receipt: {sequence, status_sequence, replayed: true}`. A conflicting digest or
   identity is rejected. It never renews, grants, writes results, increments
   events or starts the notification worker.

Responses use `agent_worker_response`, the same protocol and request ID, and either
`ok: true` with operation-specific data, or `ok: false` with a bounded error
code. Binding hashes and pairing secrets are never included. Lease capabilities
appear only in the authorized worker's encrypted job/renew response, never in
public worker metadata or original-App events. Responses to validly framed
requests include `request_digest`: SHA-256 of the compact, sorted-key UTF-8 JSON
request (including `attempt_id`), excluding only the ingress-added `message_id`,
`conversation_id`, `source_message_id`, and `_client_route_id` fields. This digest
is a correlation check, not a substitute for Signal authentication. The client
does not allow callers to override transport fields or attempt IDs. Incoming
worker responses are correlated to an existing local waiter, or ignored, without a worker-level reply, preventing
response loops. Unsupported operations and malformed/oversized worker controls
(over 16 KiB JSON) never fall through into an Agent chat request.

## Local RPC Client

`agent_worker_mqtt.worker_rpc_client(bridge)` is an explicit local entry point.
It is not called by inbound requests and does not enroll a contact, launch a
model, create a new MQTT subscription or allocate a thread. The explicit headless
controller calls `request(route, operation, fields, request_id=..., timeout=...)`
from its own bounded control worker. Do not call it from an MQTT ingress callback:
the response must be able to use that route's serial ingress lane.

The client binds each waiter to its exact current pair (including grant and keys),
route, request ID and attempt digest. It checks both authenticated source identity
and the current pairing binding before accepting a response, then rechecks the
binding before returning it. A duplicate, unsolicited, malformed, stale-attempt,
cross-route or expired response cannot complete the waiter. Closing the bridge
wakes pending waiters with a closed error; inbound traffic cannot recreate them.

Default limits are 128 pending RPCs globally, 16 per route, 8 MiB of accounted
request/response JSON globally and 1 MiB per route. Response framing has a 2 KiB
allowance above the existing 512 KiB job-body limit. Outgoing request JSON reserves
1 KiB below the 16 KiB ingress limit for envelope-added metadata. Timeouts use a monotonic clock
and are at most 30 seconds. Count and byte limits include completed responses
until their waiting caller releases them. These are protocol storage bounds, not
an exact Python RSS bound. Admission is rejected rather than queued indefinitely.
The client does not force-cancel transport IO already inside the existing sender.

Outgoing calls use existing Signal encryption and opaque paired Link topics with
`durable=False`: an offline outbox must not silently send an obsolete poll or
renewal later. This does not disable encryption. Transport failure and timeout
remain ambiguous, so the controller must retry the same logical request ID and
sequence. Each retry gets a fresh attempt ID and envelope; coordinator idempotency
still prevents duplicate grants/reports. A delayed response from an earlier
attempt cannot be paired with a newer send timestamp to falsely extend a lease.
Responses contain monotonic send/receive observations for a future lease guard;
the RPC layer alone does not enforce tool cancellation or execution deadlines.

## Session And Capacity Boundary

Re-enrollment, revocation or replacement of a worker process invalidates its
previous active execution leases in the same database transaction. Old session
heartbeats cannot revive the previous process. A new process must observe the
current session epoch before connecting; it cannot reset the counter to zero.

Public capacity becomes zero when a worker has not been seen for 30 seconds or
when the coordinator clock precedes its last observation. Capacity is a worker
advertisement, not proof of completed work. The durable scheduler also subtracts
outstanding grants and enforces provider/App/conversation fairness. An expired
lease does not prove the previous process stopped and does not release its slot.

The registry stores at most 10,000 enrolled routes, including revoked entries.
This is not evidence that 10,000 model processes can run simultaneously.

## Job And Report Data

An authorized job contains only `provider`, `prompt`, allowlisted restored request
`options`, and `lease`. The full internal task record, storage revision, pairing
credentials and contact state are not serialized to the worker. The lease has
`key` = `[App, conversation, turn, task, generation]`, `epoch`, `token`, and
`expires_at_ms`. Worker identity is derived from its authenticated session, not
accepted from that object. The worker must persist and deduplicate grants by full
execution key and lease epoch before starting tools. Server timestamps do not
replace the need for worker-side monotonic deadlines.

Job JSON is bounded at 512 KiB, with prompt at most 256 KiB. Input image snapshots
can carry the existing attachment descriptors/base64 data. A record with input
attachments but no restorable attachment snapshot is rejected, not silently sent
as text-only. Encoding/size validation runs in the same transaction as dispatch,
so a rejected job does not leave an orphan lease or consume capacity.

```json
{
  "type": "agent_worker_report",
  "protocol": "galaxyssi.worker-control.v1",
  "request_id": "report-1",
  "incarnation": "worker-process-1",
  "session_epoch": 1,
  "sequence": 1,
  "lease": {
    "key": ["app-example", "conversation-example", "turn-example", "task-example", 1],
    "epoch": 1,
    "token": "capability-from-the-encrypted-grant",
    "expires_at_ms": 1788914000000
  },
  "report": {"status": "completed", "text": "Result", "error": "", "current_step": "Done"}
}
```

Report status is `running`, `completed`, `failed`, `cancelled`, or `timed_out`.
The text limit is 8 KiB UTF-8, error 2 KiB, current step 1 KiB. Extra report fields
are rejected, including arbitrary task records, paths, output files, routes and
policies. Oversized text is rejected rather than truncated; chunked long output
and produced artifacts still require a follow-up transport implementation.
Completion requires nonblank text and no error. Other terminal statuses require
an explicit error/reason. These reports describe worker observations; they do not
implement a remote pause/cancel command channel.

The latest identical normalized report replays its receipt without advancing
task revision, status sequence or Run events. Changed/reordered reports, replaced
incarnations, revoked grants and expired leases are rejected. Per-task worker
report sequences are mapped to coordinator-owned UI status sequences.

## Durable Original-App Delivery

Report receipt, task/Run state, terminal slot release and notification checkpoint
commit in one SQLite transaction. A normal retry-thread pass drains up to eight
notifications through the existing encrypted status/result delivery path. The
destination comes from the original task, never from the worker report. No
per-task delivery thread or new broker subscription is created.

Notifications survive coordinator restart and are rotated after attempts so an
offline App does not permanently block later entries. Acknowledgment compares
generation and status sequence, preventing an old send from deleting newer
progress. Lease capabilities are not part of public task projections. This
outbox supplements, rather than replaces, transport delivery ACKs and the
existing durable result archive.

## Remaining Work

- Headless worker execution controller using the paired RPC client and the local
  grant/report journal, pairing UX and operator enrollment UI. Desktop 1.1.30 adds
  the callable Windows Codex adapter and local lease guard, but not automatic
  worker activation; see `../architecture/desktop-worker-local-execution.md`.
- Normal-App admission/routing into the worker queue and actual provider execution.
- Remote cancellation, chunked long output, artifact transport and multi-node recovery.
- Run large-node encrypted saturation tests against the bounded ingress pool
  introduced in Desktop 1.1.28; see `../architecture/desktop-bounded-mqtt-ingress.md`.
  Its synthetic queue tests do not prove real-node throughput or whole-process bounds.
- Wire the local monotonic worker deadlines into the controller, add coordinator clock-regression handling and prevention
  of stale external side effects after disconnection/revocation.
- Real broker tests with two independent worker processes, then real model and
  physical multi-host failover validation.

No production device is enrolled by the tests. The focused ingress test stubs
Signal decryption and exercises the real message router; it is not a cryptographic
or multi-host integration test. Existing S20U real delivery tests remain separate.

## Verification Record

On 2026-09-09 the expanded task/worker/MQTT regression passed 314 tests and
194 subtests. After explicit protocol-version validation was added, 15 focused
worker registry/API/ingress tests and 12 subtests passed. Coverage overlaps.
Desktop's 29 Node tests, structure check, repository checks and diff checks passed.

Desktop 1.1.24 was started with the existing paired state. The unauthenticated
operator endpoint returned HTTP 401 in the running application. No real worker
enrollment was created. S20U SM-G9880 Android 1.1.12 (898), unchanged and not
reinstalled in this round, passed four real text/image MQTT/model/App requests
across two interleaved conversations in 28.833 seconds. Text took 12,944/14,574 ms;
images took 13,142/9,591 ms, including full equation recognition. Both task pools
were idle afterward. These are ordinary Agent requests, not remote worker jobs.

Ignored local evidence: `build/s20u-worker-mqtt-enrollment-live.log` and
`build/s20u-worker-mqtt-enrollment-device.log`. Main was fetched and synchronized
through `75dc4d6ad` before submission; its final delta was Android-only neural
embedding work and did not change the tested Desktop code.

### Dispatch And Receipt Adapter, Desktop 1.1.27

The extended task/worker/MQTT regression passed 382 tests and 228 subtests in
85.70 seconds. It includes durable delivery, publish registration, subscriptions,
the 10,000-record queue, and the initial protocol scenarios. After additional
copied-lease, concurrent-notification and transport-error scenarios, the final
worker protocol/registry suite passed 32 tests and 27 subtests in 9.47 seconds.
These suites overlap and are not additive. Root checks, all 29 Desktop Node
tests, and Desktop structural checks passed.

The ingress test exercises the real encrypted-message routing boundary with
Signal decryption stubbed; it performs connect, heartbeat, poll and report,
rejects a forged application source, and verifies no Agent chat starts. Other
tests cover structured report allowlists, idempotent normalized receipts, old
worker incarnations, expired/cross-worker leases, preserved input image snapshots,
transaction rollback and restart-persistent original-App notifications. They do
not execute a real remote worker or establish a multi-host cryptographic session.

Desktop 1.1.26 was an intermediate runtime validation (four ordinary S20U requests,
31.162 seconds). A subsequent transport-error classification correction received
a new version, 1.1.27, rather than reusing the deployed version number. Both
restarts used normal window closure after verifying the normal/control pools
were idle; no process was forcibly terminated.

Final 1.1.27 runtime validation used only S20U SM-G9880, still Android 1.1.12 (898).
No APK was rebuilt, no worker was enrolled, and pairing/history were preserved.
Two private generated-fixture conversations each sent text followed by a PNG
equation. Four of four replies passed exact contact/source/conversation/turn/task
matching, success, generation 1, unique marker and complete equation assertions.
The instrumentation completed in 28.370 seconds:

| Request | Source message | Latency |
| --- | --- | --- |
| Conversation A text | 1788914590785 | 12,920 ms |
| Conversation B text | 1788914590786 | 12,037 ms |
| Conversation B image | 1788914590787 | 10,618 ms |
| Conversation A image | 1788914590788 | 13,076 ms |

Final health was ready, MQTT connected with 10/10 subscriptions, and both work
pools idle. The running unauthenticated worker operator endpoint returned HTTP
401. Ignored local evidence: `build/s20u-worker-receipt-protocol-1.1.27-live.log`
and `build/s20u-worker-receipt-protocol-1.1.27-device.log`. This real device run
is a regression of the normal single-node Agent path, not remote-worker or
multi-host acceptance. Main was synchronized through merge `5d1c5b2aa` before
submission. Its final delta was Android-only encrypted vector checkpoint work;
the tested Desktop sources did not change and that Android build was not installed.

### Paired RPC Client, Desktop 1.1.29

On 2026-09-09 the task/worker/MQTT regression passed 534 tests and 259 subtests
in 124.08 seconds. After reserving request framing headroom, the focused RPC,
protocol and registry suite passed 52 tests and 53 subtests in 8.27 seconds.
These results overlap. Repository checks, all 29 Desktop Node tests and Desktop
structural checks passed. Upstream was fetched through `ae1e98b57` before submission.

New coverage includes ten out-of-order concurrent RPCs with distinct execution
keys, the same request ID on two paired routes, fresh attempt correlation on an
idempotent retry, late/duplicate/forged responses, pairing changes, count/byte
admission bounds, 1,000 rejected extra routes, response-budget isolation, close
cleanup, and framing boundaries. The client executes connect, heartbeat, poll,
renew and duplicate report RPCs against the real coordinator protocol in a local
test fixture. Another test exercises the production envelope ingress with Signal
decryption stubbed; it verifies that forged application sources do not complete
a waiter and no ordinary Agent request starts.

These are local protocol/concurrency tests, not ten real model tasks or a remote
worker deployment. No real contact was enrolled. Desktop 1.1.28 remained running;
1.1.29 was not deployed and no APK was rebuilt or installed in this round. The
previously denied automated phone-test launch was not retried or bypassed. There
is no new device text/image acceptance result for this version. Real worker
execution, durable worker-side recovery and physical multi-host acceptance remain
open requirements, alongside the existing ordinary S20U delivery evidence above.

### Explicit Controller, Desktop 1.1.31

The [worker controller](../architecture/desktop-worker-controller.md) connects
these RPC operations under explicit local operator activation. It persists
logical requests before sending, retries receipt delivery without model replay,
renews active and queued grants, and borrows the normal Desktop model pool.
Pairing or incoming messages do not activate execution. No wire operation changes
are introduced. Interrupted controllers retain a recovery fence. Desktop 1.1.32
can reconcile already committed terminal receipts without repeating model work.
Desktop 1.1.33 holds a local OS ownership lock from recovery through controller
shutdown and verifies recorded Windows Job Objects before recovering a hard-exit
checkpoint. Missing outcomes and ambiguous grants remain fenced. These local
recovery additions do not change wire fields; general uncertain-job recovery and
real multi-host/phone acceptance remain outstanding.
