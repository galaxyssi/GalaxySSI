# Android #3039: mixed-live primary partition compaction

Android merge: `704357097339a579704356976832ec2f74e0a3df`.
Incremental predecessor: iOS #4603 at
`2931b3745de15e95f917d306f7adb15ac54cafdd`, including #4602, #4601,
#4600 and #4596. This formal PR targets main with those shared ancestor
commits. Its full-main review includes physical primary partitions, batches,
leases, periodic maintenance, checked durability, allocation recovery,
statement reuse and bounded cached readers, not only this increment.

## Prepared-source and committed-view integration

The branch now merges updated #4602 at `b3fb18e58`, including updated #4596 and
the #4625/#4623/#4621/#4619/#4616 source preparation, checked imports, streamed
observation, committed lexical/vector reads and timing prerequisites. The
original #4603 read-connection implementation remains common ancestry. These
prerequisites are part of the full main diff, not newly delivered #3039 work.
The base remains main and no merge wait, duplicate PR or author approval is
needed to review this integration.

Retain the newer catalog transaction, physical batch, generation fencing and
managed private-view teardown. Physical compaction updates only authenticated
primary references and compaction/allocation/retirement state: it must not edit
logical knowledge rows, source generations, FTS or vector feeds. A prepared
source therefore remains valid through pure compaction, but an actual source
mutation still conflicts. This does not change the separate legacy inline-body
migration's conservative generation conflict behavior.

Production committed views hold independent physical snapshot leases through
candidate/current validation, read callbacks and managed SQLite close. Existing
EX admission defers compaction while such a view is active. After the view closes,
the existing retirement boundary drains idle cached physical readers before
unlinking files. No early release or writer-lock fallback is introduced.

Four new synthetic integration methods cover preparation across compaction with
unchanged logical source revision/vector feed/outbox receipts, actual candidate
view deferral, targeted replacement/deletion between pages without resurrection,
and failed targeted writes preserving references/dirty work/active state/outbox.
These methods are authored only, not compiled or executed. The complete storage
scope now contains 206 authored methods: the updated #4602 chain's 163, the
existing 24 read-connection and 15 compaction methods, and these four cases.

The read-connection guard now compares complete retained files/project content
to pinned updated #4602. The compaction guard retains exact previous physical
implementation comparisons and pins new catalog/statement prerequisites
explicitly. Existing assertions are not removed to hide integration changes;
the compaction check also invokes the prepared-source/view integration guard.
Static contracts are not native concurrency, crash, performance or power-loss
evidence. No Android measured result is an iOS acceptance result.

## Durable work selection

Add small primary dirty/state tables and mutation triggers transactionally in
the existing primary setup, without a whole-catalog startup count or scan.
Persist discovery cursor/completion and an active source. Discover at most
32 partition keys per step; select at most eight dirty candidates; relocate
at most eight currently referenced records. Partition insert and reference
delete/move enqueue affected work, including keys behind the discovery cursor.
Healthy candidates leave the queue until another mutation. Empty partitions
enter the existing retirement queue. Select a mixed partition when its live
reference count is at most half its recorded appends, then seal it so future
normal writers cannot refill that source. The membership count uses the
existing partition-reference index; it still visits one partition's references,
not a constant number of rows or a hard time bound.

These additive primary tables do not change the application's existing catalog
user_version or reuse Android's schema number. Existing authenticated namespace,
reference and frame formats remain readable and unchanged. Unknown/unpublished
physical waste is not counted as a recorded append.

## Streaming relocation and publication

The existing reclaim entry point, already reached by the independent periodic
storage worker, now advances compaction before physical retirement. Hold the
existing writer/reader owner locks, nonblocking cross-process EX file lease,
and an IMMEDIATE catalog transaction. Do not call public batch/append methods
that would reacquire the owner lock or downgrade EX to SH. An internal owned
batch flushes every physical destination, syncs its directory, runs the existing
publication fault boundary, checks catalog durability and only then commits
catalog references and compaction state. Rollback closes/rolls back outstanding
physical writers and clears the owned batch on every failure path.

Share the unchanged reference authentication/validation with ordinary reads.
Walk contiguous frames with cancellation checks, authenticated source AAD,
bounded decode, expected per-frame lengths and an incremental complete-body
SHA-256. Bound the SQL-selected ciphertext prefix to 196,609 bytes, one beyond
the accepted 192 KiB frame maximum, so an oversized frame fails validation.
Re-encrypt each compressed frame with destination/item/entry/ordinal-bound AAD;
do not assemble an entire body for relocation. Ordinary reads still collect
their complete result through the same authenticated walker. This is not a
claim that arbitrary SQLite/VFS memory use or ordinary complete-record read
memory is bounded by one frame.

Retain frame count, plaintext size, hash and logical records. Require exactly
one item/source reference update and overflow-checked destination append
accounting. Staged references cannot become visible until destination frames
are durable. Remaining source references are the restart checkpoint: user
replacement/deletion between steps wins and no stale copied body is resurrected.
Retire source metadata only after its final reference disappears. Unlink follows
catalog commit through the existing persistent queue, descriptor-relative
sidecar preflight, cached-reader invalidation and directory synchronization.
Independent snapshots defer the whole operation. The page result adds a moved
record count; existing caller defaults remain valid.

## Recovery and remaining work

A failure before physical commit keeps old references authoritative. A failure
after physical commit but before catalog commit can leave unreachable destination
frames, never a partially published record. Newly allocated unpublished files
remain recoverable through the existing allocation journal. Unreachable frames
inside an existing registered partition are not exactly accounted for. A failure
after catalog commit but before unlink retains the retirement queue and the new
authoritative reference. No unknown orphan inventory or power-loss proof is
introduced.

The bounds are work pages, not a corpus cap or universal latency guarantee. A
single exceptionally large record can outlast a maintenance quantum and retry
from its beginning. Android #3040's durable per-frame copy and verification
checkpoints remain separate required work. Header/FTS/vector control sharding,
exact dead-byte accounting and full #3037 parity also remain incomplete. No
model/provider, network, plaintext file or new OS scheduling entitlement is added.

## Verification limits

Fifteen synthetic Swift methods authored and registered, not compiled/executed:
mixed partition relocation/retirement; eight-record restart pages; between-page
deletion/replacement; multiframe binary hash preservation; healthy candidate
removal/re-enqueue; failure before frame commit; physical commit before catalog
failure; cooperative cancellation; corrupt/oversized frames; corrupt encrypted
reference; independent snapshot deferral; committed references before failed
unlink; 32-key discovery/eight-candidate selection; retained EX lease at physical
and catalog publication hooks; actual background storage slice preserving logical
items/source revision across reopen. Injected throws and object reopenings are
not real process-death, reboot or hardware durability evidence.

The full-main scope contains 109 authored Swift methods, not 109 passing native
tests. The new source guard pins the predecessor and reverses only declared
reference extraction, streaming walker, queue/reclaim and project hooks. Older
reader/statement/allocation/durability/primary assertions remain active through
a checked normalization hook. Source checks cover six scope guards and their
JavaScript syntax, iOS project structure, changed-source/document literal-Han
placement and diff whitespace. No Swift compile/typecheck, native SQLite/
filesystem/concurrency/XCTest run, device data, CI watching, IPA, author approval
or merge. No Android measured speedup, full npm check pass or entire backlog
completion is claimed.
