# Android #3037 authoritative knowledge partitions

Pinned Android merge: `7b8b6d2a840e8db70deca680233603113d53f36b`.
Incremental main base: `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.
The eight changed Android production files are individually pinned and
dispositioned in `ANDROID_3037_SOURCE_INVENTORY.json`. Android version changes,
instrumentation infrastructure and device measurements are not copied or claimed
as iOS acceptance. This is a substantive storage integration, not full #3037
completion.

## Actual read/write integration

New authoritative records, small and large, now use encrypted physical SQLite
partitions through `AgentKnowledgeDatabase.insert`. The existing catalog keeps
its item/source/FTS/vector/control schemas and stores an authenticated primary
reference; inline ciphertext and legacy per-record files remain readable only
when no primary reference exists. A corrupt primary pointer/frame throws rather
than silently returning a legacy copy. New writes fail closed if primary storage
cannot be prepared; they do not pretend to have committed via another backend.

Four buckets use the existing keyed record hash. Partitions rotate at about
64 MiB of appended sealed-frame bytes or 65,536 appended records. These are
rotation targets, not corpus limits or exact physical file-size guarantees;
SQLite/WAL/metadata overhead and orphaned append frames can add space. Each store
retains at most four writer connections and serializes one transient reader.
The catalog writer lock and SQLite catalog transaction still govern logical
writes; snapshot reads use their own catalog handle.

Frames contain at most 64 KiB of original record bytes. Apple Compression ZLIB
with a raw fallback is an internal iOS representation, not Android's GZIP format
or a new backup/wire schema. Bounded decoding checks frame expansion, sequence,
tail, total bytes and whole-record digest. Existing AES-GCM cipher purposes bind
the catalog namespace, record hash, partition, entry and ordinal. The reference
is separately sealed. No plaintext record ID/body is used as a filename.

The random catalog namespace is sealed and persisted, and its key account is
bound to the stable catalog filename. It does not depend on the container's
absolute path. Authoritative partition files are NOT excluded from system backup.
Logical backup/export continues to enumerate the existing database snapshot API;
this is not a raw cross-platform database format or key transfer protocol.

## Publication and migration

Immutable frame transactions commit with SQLite FULL synchronization before
catalog reference publication. The outer catalog transaction then publishes the
reference/item/index changes. A failed catalog publication can leave unreachable
physical frames, but cannot point at an uncommitted frame transaction. Subsequent
updates get a distinct entry ID; old snapshot references keep their original
frames. No atomic transaction across multiple SQLite files or power-loss proof
is claimed.

Actual coordinator startup starts an idempotent, weakly owned serial utility
worker. It advances eight-record pages with a persisted cursor and yields between
pages. Database construction alone does not start it, so explicit read/snapshot
and fixture instances do not acquire a background worker. A page owns one catalog
write transaction, validates the original complete record, appends and reads back
the new primary data before replacing the inline body with a sentinel. Cursor
publication shares that transaction. A failed/cancelled page rolls back its
catalog changes. Storage errors stop the worker; another explicit start or cold
startup can resume from the committed cursor. This is not Android WorkManager
or an iOS OS-background-execution guarantee.

Only physical ownership changes: no source/header revision, FTS tokens, native
index token or vector feed/provenance writes are added to migration. Legacy
external references/files are deliberately retained so an already-open catalog
snapshot is not invalidated. The old externalizer skips new primary records,
and its original old-format behavior remains covered by explicit legacy fixtures.

## Remaining implementation

- Snapshot-safe cleanup of retained legacy external copies is NOT implemented
  here. Their references/files are still retained. Unknown orphan discovery and
  mixed-live compaction were not delivered by the pinned Android PR either.
- Physical commits are currently per record, before catalog publication. Native
  bulk partition-transaction batching and its performance investigation remain
  open; no latency improvement or universal resource-bound claim is made.
- Complete record encoding/materialization, FTS and logical catalog work still
  have their existing memory costs. Per-frame bounds are not a full-record or
  whole-corpus memory guarantee. Native crash/fault, migration/backup/privacy,
  concurrency, connection-cache and scale acceptance remain unverified.

## Source evidence

Fifteen XCTest methods are authored only, NOT executed: compressed/raw/binary frame
bounds, Unicode multi-frame/reopen, rotation across four buckets, failed catalog
publication, old snapshot retention, swapped/corrupt references, missing/corrupt
frames, container relocation, resumed old inline/file migration with unchanged
source/vector records, and actual small/large database writes. Two existing legacy
tests now explicitly seed the pre-primary physical format; their original
assertions are retained. Native fixture cleanup includes the new private root.
Five additional methods cover snapshot/second-store deferral, interrupted queue
replay before/after unlink, live-reference/traversal/symlink rejection, bounded
pages and preservation of unknown files. These are not executed crash or device
acceptance results.

`check-knowledge-primary-partitions-scope.cjs` verifies pinned production sources,
complete retained coordinator/catalog code outside declared hooks, actual writer/
reader/migration/worker wiring, publication order and project registration.
Source/project/diff checks are not Swift type checking, executed SQLite/CryptoKit/
Compression tests or migration acceptance. No native build, XCTest execution,
CI watching, Android/Desktop change, version bump or IPA is performed.

Compression API reference: [Apple buffer compression documentation](https://developer.apple.com/documentation/accelerate/compressing-and-decompressing-data-with-buffer-compression).

## Whole-dead partition reclamation

Every store holds a shared advisory file lease. Search/export transactions also
hold their own shared lease until after rollback and SQLite handle closure, so
the same store cannot unlink a partition still needed by one of its old snapshots.
The catalog-serialized reclaimer closes cached writers before attempting a
nonblocking exclusive conversion. Other stores (including idle live instances)
or pinned snapshots conservatively defer reclamation; the worker retries after
five seconds instead of spinning. All reads/writes recheck the shared lease if a
failed conversion or downgrade dropped it. The lock file is never retired.

Under the exclusive lease, at most eight known, wholly unreferenced partitions
are queued per normal worker page and removed from allocation metadata in one
catalog transaction. That transaction commits before any unlink. The persisted
retirement queue survives failures before/after unlink; missing files are
idempotent on retry. Current references are rechecked before deleting each entry.
Only canonical UUID basenames and regular files in an anchored, non-symlink
directory are eligible. No directory scan, recursive delete, unknown-file cleanup
or live partition compaction is performed. The queue entry is cleared only after
sidecars/database unlink and directory synchronization succeed. Native Darwin
flock/filesystem/crash behavior remains unverified by execution.

Lease API reference: [Apple flock manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html).
