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
silently erase it or rerun the model. Desktop 1.1.32 adds the bounded committed
receipt recovery described below. Automatic process-loss reconciliation,
coordinator failover and accepting previously uncommitted expired results remain
**not implemented**.
Do not delete the journal to bypass this fence. A recovery protocol must reconcile
remote lease/receipt state and owned-process quiescence first.

### Committed Receipt Recovery, 1.1.32

If the terminal report is already staged and its grant expires while the
controller is running, it retains the slot and uses the read-only
`agent_worker_receipt` RPC. A matching committed receipt confirms the local
journal and releases the slot without another model dispatch. Missing receipts
are checked at bounded five-second intervals; authorization/identity conflicts
remain fenced. Ordinary reports and renewals still require a live lease.

When a stopped controller is activated again, the local API first tries to
reconcile its persisted report/receipt intents. Queries bind the original
coordinator pairing, owner, five-part identity, lease epoch/token and exact
normalized report digest. Query IDs are deterministically derived from persisted
intent IDs. Recovery does not connect, poll, renew, submit a report or run a model.
At most 20 report/receipt intent rows are visited, with a ten-second scheduling
budget and at most one second per RPC wait. As with ordinary RPC, sender IO that
is already running cannot be forcibly cancelled; this is not a hard wall-clock
bound on the underlying transport.

Confirmation precedes atomic intent cleanup and completion-count update. A crash
between them safely repeats the read and cannot increment the completion count
twice. A missing receipt, outstanding poll, unconfirmed local job, changed pair
or still-open old owner prevents clean reactivation. Only confirmed old jobs and
non-execution control intents permit the store to close for a new activation.
This supports recovery after a controlled stop, including a subsequent restart;
a hard crash leaving an `open` marker still needs owned-process reconciliation.
No process or journal is deleted to make a recovery test pass.

A heartbeat-expired rejection refreshes heartbeat before retrying the same
logical poll/renew/report. An explicitly rejected poll with no ambiguous earlier
attempt does not reserve capacity in the replacement heartbeat; the reservation
is restored before its next send. Once a transport failure has made that logical
poll ambiguous, a later heartbeat rejection cannot prove it was never granted:
its reservation is retained.

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

### Final Receipt-Recovery Verification, Desktop 1.1.32

- Expanded regression: 617 passed, 312 subtests, three opt-in live cases skipped,
  in 100.53 seconds.
- After tightening reservation handling for a previously ambiguous poll, the
  final recovery/controller/protocol/RPC suite passed 66 tests and 57 subtests
  in 25.69 seconds, with two live cases skipped. These suites overlap.
- Both final controller live cases were explicitly run: two passed in 55.73
  seconds. They made four real Codex calls across text/native-PNG scenarios,
  including dropped report acknowledgements and successful read-only receipt
  recovery after actual lease expiry. This is total test time, not model latency.
- The expiry case first passed separately in 38.45 seconds before the final
  poll-reservation correction. It does not count as additional unique coverage.
- Coordinator/transport remain in-process fixtures. No physical phone, real
  broker worker enrollment or multi-host recovery acceptance is implied.
- Root checks, all 29 Desktop Node tests and structure passed. Upstream remained
  `a17525ba0`. Source/package metadata is 1.1.32; no APK/installer was built and
  the running Desktop was not replaced. Its health was ready/ok with MQTT
  connected and ten active subscriptions after testing.

### Deployment Update, 2026-09-09

- Desktop 1.1.32 was launched from commit `c5078244c` after checking both the
  model and control pools were idle and closing the previous window normally.
  The new backend exposes the worker-client API; unauthenticated access returned
  401. Health reported ready/ok, Signal sidecar ready and ten of ten MQTT
  subscriptions active. No real worker enrollment was enabled.
- S20U (SM-G9880) was updated in place from Android 1.1.12 (898) to the current
  main Android sources, 1.1.18 (904), using `adb install -r`. No uninstall,
  application-data reset or pairing reset was performed. No other phone was
  operated on.
- The complete debug APK was built with embedded-runtime validation enabled.
  The initial 2 GiB build reported insufficient heap; after verifying the build JVM's
  identity and near-full heap, only that build JVM was stopped. A new build with
  `--max-workers=2` and `-Dorg.gradle.jvmargs="-Xmx4096m -Dfile.encoding=UTF-8"`
  succeeded in 5 minutes 18 seconds. Project Gradle settings were not changed.
- Artifact size: 414,984,464 bytes. SHA-256:
  `428328fac7c1ea508b42a11450774efbef800ae297773f3303ff12b35119dbcf`.
  Output metadata and the installed package both report 1.1.18 (904).
- APK signature verification passed using v2. The 16 KiB audit passed for 73
  Android AArch64 libraries; the QNN audit passed for 24 required libraries.
  Archive inspection confirmed Linux 1.3.9 and Python/uv 0.12.1 bundles, the QEMU
  manifest and `libgalaxyssi_qemu.so` were included.
- The normal launcher opened MainActivity. A screenshot showed the rendered
  header and input area, and the observed crash buffer was empty. This was a
  warm launch, not a cold-start benchmark. The phone logged MQTT connection and
  subscription to rotating opaque relationship mailboxes after updating.
- Private screenshot evidence remains outside Git at
  `build/reports/deployment-1.1.32/s20u-startup.png`.
- These observations prove installation and startup/connectivity, not model
  response delivery. Fresh phone-origin text/image requests and original
  App/conversation/turn/task/generation receipt checks are still required.
  Manual test input was requested; the previously denied automated phone-test
  launch was not retried or replaced with an equivalent automation.
