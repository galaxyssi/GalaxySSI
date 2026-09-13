# Resumable primary partition compaction

Android 1.1.113 adds physical reclamation for primary partitions containing both
live and obsolete records. This follows primary body sharding and bounded SQL
statement reuse. It does not complete the 100-million-record memory goal.

## Selection and bounded discovery

Schema 15 adds an indexed dirty-partition queue and a single persistent discovery
and active-source checkpoint. Opening an old store creates only these tables and
triggers; it does not count or copy every memory. Background discovery visits at
most 32 partition keys per step using keyset pagination. Inserts and reference
deletions/moves enqueue affected partitions transactionally, including partitions
inserted behind the discovery cursor.

Each step examines at most eight queued candidates. A membership-index count is
limited to one partition's live references, rather than the entire memory table.
Normal partitions roll over at 65,536 appended records or approximately 64 MiB.
A partition with no references enters the durable retirement queue. A partition
with at most half its recorded appends still referenced becomes a compaction
source. Healthy partitions leave the queue; later mutations enqueue them again.
The source is sealed before moving records so later writers cannot refill it.

The recorded append count does not include frames committed before a rolled-back
catalog publication. Unknown orphan files and such uncounted physical waste are
not discovered or accounted for by this phase.

## Publication and recovery

The existing background payload maintenance worker invokes this path only under
the cross-process exclusive snapshot lease. Backup/search snapshots defer it.
The operation also holds the owner monitor and the catalog writer transaction.
At most eight live records move per step. Their existing encrypted catalog
references are the checkpoint: a later step queries only references still owned
by the source. Concurrent replacements/deletions between steps cannot resurrect
old bodies.

Relocation validates reference authentication, frame authentication, contiguous
ordinals, decoded size and UTF-8 through the existing frame codec. One bounded
compressed frame and its decoded text are handled at a time. The compressed
frame is re-encrypted with destination-bound AAD; relocation does not assemble
the entire body or alter logical item rows, revisions, FTS or vector documents.

All destination transactions commit with the existing FULL durability settings
before the catalog publishes new references and its checkpoint. A crash before
catalog commit leaves old references authoritative. A crash after catalog commit
leaves destination frames durable. The old source enters the persistent retirement
queue only after its last live reference moves or is deleted. Unlink happens after
catalog commit, under the same exclusive lease, and survives interruption through
the retirement queue.

Cancellation is checked during discovery, selection, each record and each frame.
An interrupted step rolls back its catalog changes. A destination already flushed
before rollback can contain unreachable frames, but no partial record is published.
There is no model call, network transfer, plaintext file or whole-memory JSON.

## Bounds and remaining limitations

- Discovery: 32 partition keys; selection: eight dirty keys; relocation: eight
  records per step. These are work-page bounds, not total memory limits.
- Frame handling is bounded; one exceptionally large record can still take a long
  step. Cancellation can discard work done on that record. A durable per-frame
  partial-record checkpoint is not implemented here. A record that consistently
  exceeds the worker's five-second quantum can repeatedly retry without progress;
  this remains a required follow-up, not a completed long-record acceptance claim.
- The background exclusive lease blocks new snapshots for the duration of a step.
  Foreground/cancellation checks let the worker yield; this is not a hard 200 ms
  maintenance latency guarantee.
- The existing catalog, metadata, FTS and vector control are still centralized.
- No unknown orphan-file discovery, exact dead-byte accounting or universal
  100-million-real-record performance guarantee is claimed.

## Verification

`tools/dev/test-knowledge-primary-compaction.ps1` targets SM-T575 explicitly.
Its focused phase covers restart checkpoints, cancellation, catalog publication
failure, corruption, deletion between steps, re-enqueue after threshold changes,
large Unicode frames, paged schema-14 discovery, retirement before unlink and
snapshot/logical-revision preservation.

The recovery phase kills a real instrumented process before frame commit, after
frame commit but before catalog commit, and after catalog commit. The host verifies
durable phase markers and then verifies retained bodies and resumed work.

The retained phase uses the existing 10,001-real-record corpus without reseeding.
It verifies every ID and complete encoded-record digest before and after compaction,
including reopenings and unchanged logical source revision. Measured results are
reported only after the tests complete.

### Retained-corpus results on SM-T575

Android 1.1.113 (999) was installed without an uninstall or reset. All 10 focused
compaction cases and the original 15 primary-storage cases passed. Three real
process deaths were verified by the host at the before-frame, before-catalog and
after-catalog boundaries, with four successful preparation/recovery checks.

The retained 10,001-real-record corpus moved through 1,253 maintenance pages,
including periodic owner reopenings. All 10,001 complete encoded records matched
their pre-compaction digest after reopening; the logical source revision was
unchanged. Compaction itself took 33,486 ms, page P95 was 41.973 ms and the slowest
page took 82.663 ms. Four old partitions were retired. Physical primary-directory
size fell from 21,127,168 to 7,008,256 bytes. Total test time, including both complete
record verification passes, was 143.699 seconds. This is not an initial-write or
source-replacement benchmark and is not an acceptance test at 100 million records.
The retained test invokes maintenance pages directly off the UI thread; its
elapsed time excludes WorkManager idle constraints and retry scheduling delays.

After compaction, 100 public reads, 100 individually committed upserts and 100
individually committed restores all completed within 200 ms. Read P95 was 13.269 ms,
upsert P95 61.522 ms and restore P95 66.286 ms. Every probe record was restored and
checked after reopening. These warm-store measurements include partition/catalog
commits for writes but exclude observers, model work, UI and network work. There
was no controlled thermal/CPU comparison against the previous phase.

The initial 95-case legacy run reported 84 passes and 11 failures. Historical
downgrade helpers removed schema-14 tables but left the new schema-15 tables while
resetting `user_version`, creating a fixture that could not represent the claimed
old version. The fixture helper now removes the compaction tables and triggers
after preserving live bodies in the old format. Production migration validation
was not weakened. Initial failures are retained in the evidence directory; the
corrected 95-case suite passed in 694.526 seconds after the fixture-only correction.

The 22-case counter suite passed in 112.290 seconds and the 97-case source,
backup and search suite passed in 264.312 seconds. Recovery was repeated with the
corrected test APK and all three real process-death boundaries passed again. A
final full-corpus verification after those regressions matched the same 10,001
record digest in 118.486 seconds; there was no further eligible compaction work.
Probe writes had increased the primary directory to 7,168,000 bytes, unchanged by
that last maintenance step. Eligible-work completion does not mean zero obsolete
bytes below the compaction threshold.

JVM validation reported 3,823 passes, five existing skips and zero failures/errors
across 547 suites. Repository checks and all 74 AArch64 16 KiB alignment checks
passed. See [the evidence summary](evidence/knowledge-primary-compaction-20260913/summary.json).
