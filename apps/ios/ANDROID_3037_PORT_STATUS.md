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

App launch registers an independent physical-storage BGProcessingTask; runtime
binding persists periodic intent without requiring an installed embedding model.
System-granted utility slices advance eight-record pages with a persisted cursor.
Database construction alone does not start a worker, and the previous continuous
foreground startup migration loop is removed. A page owns one catalog
write transaction, validates the original complete record, appends and reads back
the new primary data before replacing the inline body with a sentinel. Cursor
publication shares that transaction. A failed/cancelled page rolls back its
catalog changes. Storage errors/expired grants retain pending intent for a later
system request. This is not Android WorkManager or a guaranteed iOS execution
interval; individual maintenance APIs remain available for explicit local work.

Only physical ownership changes: no source/header revision, FTS tokens, native
index token or vector feed/provenance writes are added to migration. Legacy
external references/files are retained during migration so an already-open catalog
snapshot is not invalidated. A later snapshot-exclusive pass verifies primary
data before releasing old references; age-gated physical cleanup uses the same
lease. The old externalizer skips new primary records,
and its original old-format behavior remains covered by explicit legacy fixtures.

## Remaining implementation

- The system background adapter is implemented, but actual OS grant/delivery,
  lifecycle cancellation and energy behavior are unverified on-device. The
  fifteen-minute earliest date is not an exact or guaranteed execution interval.
- Unknown primary orphan discovery and mixed-live compaction were not delivered
  by the pinned Android PR either.
- Physical commits are currently per record, before catalog publication. Native
  bulk partition-transaction batching and its performance investigation remain
  open; no latency improvement or universal resource-bound claim is made.
- Complete record encoding/materialization, FTS and logical catalog work still
  have their existing memory costs. Per-frame bounds are not a full-record or
  whole-corpus memory guarantee. Native crash/fault, migration/backup/privacy,
  concurrency, connection-cache and scale acceptance remain unverified.

## Source evidence

Twenty primary-store XCTest methods are authored only, NOT executed: compressed/raw/binary frame
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
Four more cover checkpointed legacy-reference pages and reopen after skipping a
legacy-only record, rollback on primary corruption, actual export/migration/file
cleanup interleaving, age gates and nonregular/symlink preservation. No native
execution of these fixtures is claimed.
An additional primary method injects cancellation between frames and checks that
the previous catalog reference/body survive. Six separate maintenance methods
cover idle/energy policy, monotonic deadlines, expired/successful completion
ownership, bounded actual-database migration/cleanup without an embedding runtime,
and cancellation/resumption. None of these twenty-six methods were executed.

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
or pinned snapshots conservatively defer reclamation; the worker yields its slice
and requests a later system grant instead of spinning. All reads/writes recheck the shared lease if a
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

## Releasing retained legacy copies

After primary migration, a separate durable cursor visits at most eight old
external-reference rows per worker page, including rows not yet owned by primary
storage. This avoids an unbounded join/filter scan in a nominally small page.
Under the shared reclaimer's exclusive lease, complete primary records are read
and authenticated before deleting their old reference rows. Legacy-only records
are skipped, corrupt primary data aborts/rolls back the entire page, and cursor
publication shares the delete transaction. A completed pass resets its cursor so
future explicit passes can revisit records that subsequently become primary.
Logical records, source revisions, FTS, vector feeds and provenance are untouched.

The old file cleaner now also requires that exclusive lease: a zero current
reference count alone is not sufficient while another catalog snapshot is open.
Busy leases return an explicit deferred result without advancing the file cursor.
The original filename, current-reference and minimum-age checks remain in force;
the payload root must be a real directory, and symlink/directory candidates are
skipped. Reference retirement does not immediately unlink any file. Failure after
reference commit leaves an unreferenced file for a later file pass, not a dangling
authoritative reference. The worker runs migration, legacy release, primary
retirement and legacy file pages in that order. Legacy migration entry points
also recheck shared access after a failed lease conversion.

The legacy file page still enumerates/sorts the existing directory before taking
its bounded candidate slice. That inherited directory-memory cost is not claimed
to be a bounded whole-corpus scan or a performance improvement.

## Periodic system maintenance

The dedicated `com.galaxyssi.chat.ios.knowledge-storage` task is registered at
application launch and permitted in both build configurations, using the existing
processing background mode. It does not share semantic-index enablement, model
installation, downloads or cancellation preferences. Database binding retains a
weak reference; cold grants look up only an existing validated history/catalog,
never create a history identity just to perform maintenance.

Each request persists intent before submitting, requires no network/external
power, and sets an earliest begin date fifteen minutes ahead. A successful empty
pass still submits a later request: newly written/deleted records and aging files
can produce future physical work. System submission refusal leaves intent for
the next launch/background transition. Requests are best-effort, not timers.

Execution requires the background application state and available protected data,
and yields during low-power mode or serious/critical thermal pressure. Foreground
entry or protected-data loss cancels the active grant and its detached utility
task. System expiration uses the same completion/cancellation owner. A generation
ticket prevents a late completion from overwriting a newly bound database's
request, and the existing completion guard prevents duplicate task completion.

One grant performs at most eight stage rounds (each at most one migration,
legacy-reference, partition-retirement and legacy-file page) and has a ten-second
monotonic cooperative budget. Checks run between pages, records/frames and before
catalog/physical publication. Expiration cancels both wrapper and detached tasks;
persisted cursors/retirement queues survive interruption. The budget is not a hard
preemption guarantee for an in-flight SQLite/filesystem call; inherited directory
enumeration remains noninterruptible until it returns. No model or network call
is part of physical maintenance. OS delivery and native behavior remain untested.

Scheduling reference: [Apple earliestBeginDate documentation](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
