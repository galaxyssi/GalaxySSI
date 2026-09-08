# Android Durable Active Plan

Android 1.1.9 (895) separates the executable plan checkpoint from compact UI and
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
the `agent_active_plans.db` encrypted-database namespace (the shared wrapper
appends `.db`, yielding `agent_active_plans.db.db`), using the existing Keystore-backed database.
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

Clearing a session synchronously commits removal of its root before removing its
own active-plan pages. The old asynchronous preference removal could be lost when
the process ended immediately, reviving a root after its pages were deleted.
Saving a null plan
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
actual process-death/recovery phases.

### Executed On 2026-09-09

Based on main `32d138ff8`, Android 1.1.9 (895) was built and installed in place on
SM-T575. No application data was cleared; only dedicated test scopes were removed.
The attached S20U was not operated on.

- 82 focused JVM tests passed across eight suites, with no failures or skips.
- Combined device instrumentation passed 26 tests; six opt-in phase tests were
  skipped in this ordinary run (the runner reports 32 total).
- Explicit opt-in phases published 2,048 actions and 2,048 checkpoints, killed
  the actual process, and recovered every node in a new process. The final
  dependency-ready node remained `node-2047`.
- A separately seeded checkpoint survived an actual tablet reboot. The boot ID
  changed from `eb134253-eb40-46c4-a920-a75ab6b207fd` to
  `e0e5a446-2257-4aa5-8a2d-7ae547256085`; post-reboot recovery passed.
- Explicit clear/kill/new-process phases verified that deleted roots and their
  scoped pages did not return. This was repeated after reboot recovery.
- Repository checks, 72-library Android 16 KiB alignment validation and the
  24-library QNN package check passed. Debug APK and instrumentation APK built.

The first implementation exposed heap exhaustion when duplicating a large graph
as JSON strings; streaming records and incremental hashing fixed it without
raising the unit-test heap. Process testing also exposed asynchronous root
deletion; committing deletion before page collection fixed that failure.

Final APK SHA-256:
`798BFAC318B075C1FF4C45D422A1E5ED78E03B63D53237C490818CEDC83CBD66`.
Device/build logs and APKs remain local, not committed. The final screenshot shows
the lock screen, so it is not evidence of the chat UI rendering successfully.

These phases verify durable checkpoints, not automatic post-boot job dispatch.
Connector tests use injected provider outcomes, not real-provider/network chaos.
Full long-running task, coordinator and performance acceptance remains open.
