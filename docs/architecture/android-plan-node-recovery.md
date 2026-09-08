# Android Plan Node Recovery

Android 1.1.6 (892). This extends the ordinary mobile plan executor on top of
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
