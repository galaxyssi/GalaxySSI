# Android Plan Node Recovery

Android 1.1.7 (893). This extends the ordinary mobile plan executor on top of
the scoped native-effect journal introduced in 1.1.5. Desktop is unchanged.

## Execution Integration

The existing Agent plan already represents dependencies and selects independent
read-only or resource-scoped mutation batches. The previous parallel path waited
for every member to return before retaining observations in its session snapshot.
A completed sibling could therefore be mistaken for an interrupted action when
another member stalled and the process died.

Both `executePlannedAction` and `executeParallelActions` now persist a node's
dispatch before execution, its returned result before handing it back to the
batch, and its verified observation before updating the plan. A sibling does not
wait for `awaitAll` before committing its returned result. The session checkpoint
is saved before dispatch so the attempt can be found after a restart.

Node keys bind session, plan, action, checkpoint attempt, conversation, turn and
the original action specification. A new checkpoint cannot consume the result
of an older attempt. Pending plan edits do not invalidate an unchanged running
node whose checkpoint and specification remain the same.

Each attempt is a child Run in the existing encrypted Run Kernel. Result text is
split at Unicode-safe boundaries into at most 24 Ki UTF-16 units per chunk. Each
returned/verified observation is an atomic chunk-plus-manifest transaction.
Readers page 64 events and verify order, digest, action and observation stage.
They do not load all node histories or store complete results in one SQLite row.

## Recovery

Session restoration and the cold-boot coordinator consult per-node observations
before converting interrupted work into failure evidence. Returned results remain
pending observation. Already-verified observations still pass through ordinary
loop continuation/finalization; they do not automatically prove the whole goal.

On resume, the runtime observes each saved result without invoking its executor
or an automatic retry. Results that were verified before interruption need no
second observation. Real failure messages and asynchronous `awaiting_response`
states are retained. Unknown siblings still require existing model assessment
and replanning. Successful known siblings are not repeated.

Recovered rolling batches request the next model-authored plan or finalization,
using the existing rolling-plan policy. A missing model proposal leaves the task
waiting for assessment, with its actual node results intact. Recovery does not
relabel a known successful sibling as an unknown watchdog failure.

Storage failures are not replaced with invented successful outputs. Corrupt
records encountered during session restoration pause with the concrete recovery
error rather than crashing initialization or silently rerunning the operation.
Cancelled and completed sessions are not resurrected by a late node record.

## Boundaries

- This is ordinary plan-node integration, not full Android migration to the
  Desktop dynamic DAG command/revision protocol.
- Native registry idempotency and node observation persistence are distinct.
  The former protects declared required-key effects; the latter retains what
  each plan attempt returned. Neither proves arbitrary external exactly-once
  execution or reconciles an operation that never returned.
- Direct calls bypassing plan execution, internal retries/rollback actions,
  provider-internal tool loops and whole-device restart scheduling still need
  explicit adapters and end-to-end acceptance.
- Dynamic graph edit fencing, durable ready-node scheduling, automatic semantic
  reconciliation and long-period runs remain outstanding.
- No provider/model, ASR/QNN, communication protocol, application data or pairing
  reset is part of this change. No cumulative action limit is introduced.

## Verification

JVM tests exercise mixed known/unknown siblings, multiple results independent of
`lastActionResult`, attempt/scope/specification isolation, changed pending plans,
actual failure preservation, asynchronous dispatch, cancellation, corruption and
cold-boot state handling. Device tests exercise encrypted SQLite transactions,
reopen, stale callbacks, large multilingual results, commit rollback, the real
parallel batch executor and the MobileNativeAgent restore/observation adapter.
The ordinary plan adapter is also exercised with real Android memory and storage
reads, not only synthetic tool outputs; no model/provider reply is fabricated.

An opt-in two-phase device test kills the actual process after the first parallel
result commits and before the second returns. The recovery phase checks that the
first observation survives and the second dispatch cannot be claimed again.
This is local process-death evidence, not a provider/network or full device-reboot
acceptance test. Executed results are recorded after running these tests; test
source alone is not a completion claim.

### Executed Evidence (2026-09-09)

The final build includes main `177601b19` (PR #2908). Android 1.1.7 (893)
was installed with `adb install -r` on SM-T575 only, without clearing app data
or pairing state. No S20U/S26U installation or model download was performed.

- Focused JVM regression: 160 tests across 13 suites; zero failures, errors or
  skipped tests. Includes plan recovery, execution continuity, cold-boot policy,
  native effects, rolling plans, transcript rendering, MQTT and Link protocol.
- New node-journal instrumentation: 10 normal tests passed. The runner reports
  12 entries because two opt-in process-death methods are skipped in this run.
- Opt-in crash phase: the process actually terminated between parallel results
  (`Process crashed.` is the expected injection outcome, not a passing test).
  A fresh instrumentation process passed the one recovery test, confirming the
  committed first result and rejecting a repeat claim for the uncertain second.
- Existing connector fallback runtime instrumentation: 12 tests passed. These
  use injected Provider outcomes and exercise MobileNativeAgent; they are not
  evidence of live Provider failures or public-network fault injection.
- The real memory/storage test executes Android hardware reads through the
  ordinary plan executor and checks positive total bytes, nonnegative available
  bytes and persisted verified results. It does not call a cloud model.
- APK build and test APK build passed. The 16 KB gate passed 72 AArch64 libraries;
  the QNN package gate passed 24 libraries (221.68 MiB uncompressed).
- `npm run check` passed after merging main and updating the version/evidence.
- Activity cold-launch smoke: `Status: ok`, `LaunchState: COLD`, 2,559 ms on this
  one sample. The main screen rendered; no new crash-buffer entries appeared
  during this run. This is not a P95 startup or responsiveness measurement.

APK SHA-256:
`65fc11270de9026ac1121acf2731787a5b809cce3da2a086be9ea6b6a4722d08`.

Local evidence is retained under the ignored `build/` directory:
`plan-node-main-integrated-build.log`, `plan-node-device.log`,
`plan-node-process-death.log`, `plan-node-process-recovery.log`,
`plan-node-connector-regression.log`, and `plan-node-t575-117.png`.
