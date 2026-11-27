# Android #3042: recover unpublished primary allocations

Android merge: `3731036db913dba7d20f3611df7df6af2c3147c4`.
Incremental predecessor: iOS #4600 at
`cace7bdadba48e0bd82d063ee8538e3ae5529042`, including #4596.
The PR targets main and retains those shared ancestor commits; the full-main
review scope includes their physical partitions, leases, maintenance and checked
synchronization, not only this increment.

## Production path

Each new partition UUID is committed to a separate versioned SQLite allocation
journal before any body file is created. Closing the journal precedes syncing
the primary directory. Catalog rollback therefore cannot erase this ownership
record. After physical creation/close, sync the directory before the second
allocation fault boundary and before catalog registration. The journal stores
opaque partition IDs, not record bodies, URLs or prompts.

The actual existing reclaim method now checks allocation work even when the
catalog has no retired/unreferenced partition rows. Replay at most eight intents
(or a smaller requested page) under the existing nonblocking cross-process EX
payload lease, outside a catalog transaction. The lease closes writers and
excludes readers/snapshots and physical mutations from cooperating processes.
Protect current catalog partition registrations and body-reference rows. Verify
regular-file types for the referenced set, requiring its main file, before clearing an
intent. Unreferenced files reuse the existing descriptor-anchored unlink and
directory-sync implementation. Clear intents in a separate journal transaction
only after verification or removal. An interrupted unlink/commit is idempotent:
the intent remains and a later replay accepts already absent files.
The durable retirement queue also retains ownership: clear its redundant
allocation intent without requiring an already-unlinked main file, and let the
retirement path finish once instead of double-counting it as an orphan.

Preflight the complete main/WAL/SHM/rollback-journal set before any unlink,
rejecting nonregular members without following symlinks. Retain unknown legacy
UUID files that have no intent. No recursive directory scan or guessed ownership
is introduced. Existing periodic storage maintenance already calls this reclaim
entry point; no new model/provider wake or OS entitlement is needed.

## Scope and limits

Reuse #4600's checked WAL/EXTRA writer policy for the allocation journal instead
of Android's DELETE journal. Retain the strict WAL/FULL catalog contract. A new
journal schema supports versions zero/one; unknown versions/corruption fail
closed. Pending body contents, namespaces, keys, compression, reference formats,
reader limits and snapshot leases remain unchanged.

Current iOS does not yet implement Android #3040's physical copy checkpoints.
No fictitious copy-checkpoint protection is claimed here; that future producer
must add its source/destination references to allocation admission. Mixed-live
compaction, unknown legacy orphan inventory, header/FTS sharding and full #3037
parity remain separate work. Reclaim counts include logically recovered intents
whose physical files were already absent, not proof that that many files existed.
SQLite/VFS/directory synchronization is not native power-loss acceptance.

## Verification limits

Ten synthetic Swift methods authored and registered, not compiled/executed:
intent-only rollback, created unpublished file/unknown-file retention, live
reference preservation, bounded paging, snapshot deferral, nonregular-sidecar
whole-set rejection, unlink-before-journal-commit replay, missing referenced
main-file retention, invalid-ID/nonregular-journal rejection and interrupted
retirement without double-counting. These inject
errors/reopen objects; they are not real process death or reboot evidence.

The source guard pins the predecessor, bounds surrounding primary/project edits
to declared hooks, checks real allocation/reclaim call sites and preserves older
assertions through a checked normalization hook. No native compile/typecheck,
SQLite/XCTest execution, live fault/restart, device, CI monitoring, IPA, approval
or merge. The full Android-to-iOS backlog is not claimed complete.

Source verification passed: allocation, durability and original primary scope
guards; all three guard syntax checks; iOS project structure; changed-source/
document literal-Han placement; diff whitespace. No inherited native fixture or
all-repository test pass is implied.
