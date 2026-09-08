# Android Durable Active Plan

Android 1.1.8 (894) separates the executable plan checkpoint from compact UI and
history projections. This follows the independent node-observation journal from
PR #2910; it does not replace the Run Kernel or introduce a second dispatcher.

## Problem

The session root encoded at most 64 actions. Recovery compaction could reduce it
further to a small set around the last action. The separate historical pages
retained at most 1,024 actions and 128 checkpoints, with truncated parameters.
Loading the root did not reconstruct the complete executable plan from history.
Consequently a large plan could lose pending nodes, dependency edges, exact tool
arguments and attempt checkpoints across a restart, even though history existed.

## Storage And Publication

`SharedPreferencesAgentSessionStore.save` now writes a lossless active plan to
`agent_active_plans.db`, using the existing Keystore-backed encrypted database.
It retains every action and checkpoint supplied by the runtime, including exact
parameters, rollback actions, descriptions, outcomes and dependency metadata.
The current goal is retained without the display text truncation. Screen context
still uses the existing privacy-oriented compact representation.

Plan records are encoded one at a time and split at Unicode-safe boundaries into
24 Ki UTF-16-unit pages. Hashing is incremental and does not quote or duplicate
the entire graph as a second large string. Reading assembles one record at a time.
Each page is authenticated/encrypted by the existing database wrapper. The root
contains a constant-size versioned reference binding storage scope, session,
plan ID, revision, page count, character count and SHA-256. It does not contain an
ever-growing list of page IDs. Complete plan content is checked before decoding.

The pages are immutable and addressed by generation plus page index. Unchanged
plans reuse the existing verified generation. Only after all pages have been written is the existing session
root committed. Old pages are collected after publication. A failed page or root
write leaves the last committed root usable; interruption may leave unreferenced
pages, which a subsequent successful save/clear of that scope collects.

Root and page stores are separate persistence mechanisms, not one cross-database
transaction. Ordered immutable publication provides old-or-new recoverability.
Process-wide striped locks coordinate save/load/clear between session-store
instances. This is not a multi-process writer lease or graph-revision CAS.

## Recovery And Deletion

New roots load the referenced graph, never their compact action preview. Missing
pages, digest/revision mismatch or a crossed scope produce a concrete recovery
error, pause nonterminal work and expose no truncated executable fallback.
Cancelled/completed sessions do not become active because of a corrupt page.

Legacy roots without a durable reference remain readable. Nodes already discarded
by an older release cannot be reconstructed automatically. A new save upgrades
the available plan; it does not invent its missing historical nodes.

Clearing a session removes only its own active-plan pages. Saving a null plan
publishes that state before collecting the previous graph. Connector response
indexing happens after checkpoint publication so an index update error cannot
cause checkpoint rollback to remove newly committed historical pages.

## Remaining Work

This restores the complete active graph supplied to persistence, not unlimited
historical retention or a fully indexed DAG scheduler. Runtime action-history
and checkpoint producers still have their existing retention policies. One active
graph is serialized/materialized by the Agent worker; scheduling does not yet
use indexed ready-node queries or delta-only graph writes. No claim of constant
memory, sub-300 ms large-graph loading or months-long device execution is made.

Full graph revision fencing, durable claims for every execution path, coordinated
device-reboot dispatch and external-effect reconciliation remain separate work.
No model/provider, ASR/QNN, transport or pairing changes are included. No fixed
action-count or task-duration execution budget is added.

## Verification

Focused JVM tests cover a 2,048-node graph, full dependency and checkpoint recovery,
large Unicode/escaped arguments, rollback actions, publication failures, missing
or modified pages, scope/revision mismatch, deletion, legacy roots and terminal
states. Instrumentation uses the production encrypted SQLite and session stores,
checks row sizes and dependency-ready selection after reopen, and includes opt-in
actual process-death/recovery phases. Executed results will be recorded after the
build and device tests; test source alone is not acceptance evidence.
