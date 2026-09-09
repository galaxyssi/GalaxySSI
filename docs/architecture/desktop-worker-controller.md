# Explicit Desktop Worker Controller

Desktop 1.1.31 connects worker status, session establishment, heartbeat, poll,
lease renewal, owned execution and terminal report acknowledgement. Pairing or
receiving an MQTT packet cannot activate it. Normal App work is not automatically
offloaded by this change.

## Operator API

All routes require loopback access and the existing `x-galaxyssi-token` header.
The remote coordinator must already have explicitly enrolled this paired worker.

| Route | Meaning |
| --- | --- |
| `PUT /api/agent/worker-client/{route}` | Explicitly start the local controller |
| `GET /api/agent/worker-client/{route}` | Read filtered status or recovery requirement |
| `DELETE /api/agent/worker-client/{route}` | Fence owned jobs and stop asynchronously |

Activation accepts `max_parallel` (integer 1..10, default 10) and `sandbox`
(`read-only`, default; or explicitly selected `workspace-write`). Unknown fields
are rejected. Codex is the only implemented provider. One controller may be
active per Desktop; identical activation is idempotent and conflicting activation
is rejected. Secrets, prompt contents and lease tokens are excluded from status.

## Bounded Shared Scheduling

The production worker executor borrows the ordinary task manager's model pool.
Local and worker model jobs therefore share the configured execution ceiling and
App/conversation round-robin queue, instead of independently creating ten model
slots each. Coordinator binding is included in a worker's App lane identity.
Queued jobs continue receiving lease renewals; their guard is checked again
before external dispatch. The worker retains at most its configured number of
grants, including queued, reporting and uncertain grants.

Stopping the controller cancels only its own queued execution keys, invalidates
only its own lease guards, and waits only for its own futures. It must not close
the shared pool or stop another session. The model pool's scheduling snapshot
includes both classes of model work. Existing interactive control work stays in
its separate bounded control pool.

Control RPCs use four threads and at most 32 pending callbacks. At most 32 durable
RPC intents and 2 MiB of request/response journal bytes are retained. Idle polls
back off to five seconds with per-instance jitter. Heartbeats run every five
seconds with retained jobs and ten seconds while idle; lease renewals are due
every five seconds. These intervals are scheduling intentions, not real-time
guarantees under OS suspension or network loss.

## Durable Communication, Not Blind Replay

Each logical RPC intent is committed before transport submission. Timeout,
publish failure and transient client pressure retry the same logical request ID
and sequence with a fresh transport attempt ID. A poll response is persisted
before model dispatch. The existing local execution journal prevents duplicate
dispatch; a staged terminal report is reused when an acknowledgement is lost.

Report acknowledgement is committed locally before the retained slot is freed.
Input bytes, execution identity and original source message stay bound through
the existing coordinator protocol. One uncertain job reserves its own slot but
does not stop unrelated work in remaining slots. Pairing changes, lost worker
authorization or coordinator incarnation changes fence the controller.

Clean shutdown permits another explicit activation. An ambiguous poll, unfinished
grant or interrupted controller persists `recovery_required`; restarting must not
silently erase it or rerun the model. Automatic process-loss reconciliation,
coordinator failover and receipt recovery after lease expiry are **not implemented**.
Do not delete the journal to bypass this fence. A recovery protocol must reconcile
remote lease/receipt state and owned-process quiescence first.

## Verification Scope

Tests cover lost poll/report replies, original identity preservation, bounded
admission, independent failure, revoked pairing, persistence failure before
dispatch, stale local owners, API authorization, shared model capacity and scoped
shutdown. The opt-in live test makes two real Codex calls (text and native PNG),
drops a terminal acknowledgement, verifies two confirmed local executions and
three report transmissions, and checks original App/conversation/turn/source/
generation fields. Its coordinator and transport are in-process fixtures, not a
real broker or another physical machine.

Still required for the overall goal: real paired-worker MQTT deployment,
normal-App routing to workers, physical phone acceptance on the deployed version,
durable restart reconciliation, output artifact transport, cleanup quotas and
multi-node failure/load tests. A 10,000-entry coordinator queue is not proof of
10,000 simultaneous model calls. No Android or Desktop runtime upgrade is implied
by a passing local test.

### Verification Record, 2026-09-09

- Expanded task/worker/MQTT/process regression: 601 passed, 302 subtests,
  two opt-in live tests skipped, in 108.14 seconds.
- Final controller suite after adding activation-to-shared-pool wiring coverage:
  14 passed, six subtests, in 23.96 seconds. This explicitly enabled the real
  Codex text/native-PNG case using the shared pool and a dropped report reply.
  Results overlap with the broader suite and must not be added as unique tests.
- Root repository checks, 29 Desktop Node tests and Desktop structure passed.
- Upstream was fetched and synchronized through `a17525ba0`; its last delta was
  Android-only model lifecycle work, with no Desktop source changes.
  Source/package metadata is 1.1.31;
  no APK or installer was built, no runtime was replaced and no pairing changed.
- The existing Desktop remained running. No new phone/broker/multi-host
  acceptance result is claimed; the denied phone automation was not retried.
