# Paired Worker Control v1

Status: enrollment, connection and heartbeat ingress implemented; task dispatch
and worker execution clients are not yet connected. No existing pair is enrolled
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
ID with the original request parameters. A transport delivery ACK confirms
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

Responses use `agent_worker_response`, the same protocol and request ID, and either
`ok: true` with public worker/session state, or `ok: false` with a bounded error
code. Binding hashes, pairing secrets and execution lease capabilities are not
included. Incoming worker responses are consumed without replying, preventing
response loops. Unsupported operations and malformed/oversized worker controls
(over 16 KiB JSON) never fall through into an Agent chat request.

## Session And Capacity Boundary

Re-enrollment, revocation or replacement of a worker process invalidates its
previous active execution leases in the same database transaction. Old session
heartbeats cannot revive the previous process. A new process must observe the
current session epoch before connecting; it cannot reset the counter to zero.

Public capacity becomes zero when a worker has not been seen for 30 seconds or
when the coordinator clock precedes its last observation. Capacity is a worker
advertisement, not proof of completed work. The future scheduler must also subtract
its own outstanding grants and enforce provider/App/conversation fairness.

The registry stores at most 10,000 enrolled routes, including revoked entries.
This is not evidence that 10,000 model processes can run simultaneously.

## Remaining Work

- Headless worker client, pairing UX and operator enrollment UI.
- Lease-aware fair dispatch, provider execution and durable application-result
  retries, preserving the original App/conversation/turn/task/generation scope.
- Remote lease renewal, cancellation, artifact transport and multi-node recovery.
- Monotonic worker deadlines, coordinator clock-regression handling and prevention
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
