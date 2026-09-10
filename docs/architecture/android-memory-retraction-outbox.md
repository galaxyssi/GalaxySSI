# Durable personal-memory retraction outbox

Android 1.1.58 extends the deletion ledger from 1.1.57 with a durable pending
projection. It does not enable global processing, change providers, send memory
to another device, or change ASR/QNN configuration.

## Commit and recovery boundaries

- A deletion transaction writes the remaining memory array, its content-addressed
  deletion record, and one pending reference per retraction chunk together.
- Pending references contain deletion hashes, not personal-memory text. They use
  the same existing Android Keystore AES-GCM encrypted database as the record.
- Each event retains its stable `memory-causal-deletion:<hash>:<chunk>` identity.
  Reading pending work uses keyset pages, without the ordinary global event
  queue's ready/overflow/dead-letter capacity rules.
- Existing deletion records receive pending references during a resumable
  bootstrap. Each page and its cursor commit atomically; the completion marker
  prevents later launches from recreating acknowledged work.
- `commitRetractionProjection` calls the persistence block before deleting any
  pending references. If persistence or acknowledgment fails, references remain
  available to a subsequent processing attempt. Retractions must be replay-safe.
- Memory backup restore recreates pending references for imported deletion
  records. The existing end-of-restore publication entry point can requeue all
  deletion records without sending them through a second queue.

## Runtime integration

The ordinary global processing loop reads the durable retractions along with its
existing events and deduplicates stable IDs within a batch. Successful projection
of the world, inbox, graphs, research/cognition state and proactive messages is
persisted before pending references are acknowledged. Pure causal retractions
skip creation of research tasks, model-deliberation tasks and proactive messages.

A separate WorkManager recovery request is scheduled after memory deletion and
on startup. It checks the existing global-enabled setting before scanning pending
work or obtaining the runtime. If disabled, it leaves the ledger untouched and
does not activate global/evolution work. Enabling global processing also requests
recovery.

Recovery calls the same processing loop in retraction-only mode, without ordinary
event processing or persistent-context synchronization. A successful batch with
remaining work schedules a continuation. A failed/no-progress batch uses durable
WorkManager backoff. The batch size is not a total action/retention limit.

Retraction failures retain their pending references and backoff after the normal
three-attempt quarantine threshold; they are not silently acknowledged or moved
to a capped dead-letter list. Ordinary event retry behavior is unchanged.
An unreadable outbox propagates an error to the dedicated recovery worker but
does not prevent the ordinary global queue from processing its own events.
Cancellation is propagated rather than interpreted as an empty outbox.

No global repository lock is held while pending memory references are read or
acknowledged. This avoids adding the reverse of the existing memory-to-global
publication lock order. The UI continuity snapshot does not perform migration
or read entire deletion records.

## Acceptance scope

Device tests use isolated encrypted databases, preserve the user's memory and
pairing, and do not enable the production global Agent. Coverage includes atomic
pending insertion, missing publication, failed projection, failed acknowledgment,
partial-batch completion, one-time bootstrap, interrupted migration and damaged
references. The acknowledgment failure test uses an idempotent test projection;
it does not prove every production graph reducer is replay-safe.

A persistent reboot fixture also retains pending references across an actual
device reboot. It records an idempotent test effect before acknowledgment, then
verifies the same pending event identities and completes them after reboot.
This verifies the storage/acknowledgment boundary, not all production projection
reducers or the production WorkManager scheduling latency.

Full cross-store crash recovery and long-run replay of all production global
projections remain required acceptance work. The existing ordinary event failure
metadata store is capped, and global model/graph evidence retention still has
its own limits; this change does not claim to remove them. An all-domain backup
restore is still not a single transaction. Knowledge deletion, neural reranking,
complete forgetting semantics, and personal-store/UI paging remain separate
parts of the Memory 2.0 goal.
Bootstrap currently holds the shared memory lock while completing its keyset
scan, although each page commits separately. Large-ledger migration latency and
contention with foreground memory requests have not passed a performance gate.
Ordinary global queue counts do not include this separate pending projection.

## Verified results (2026-09-10)

- Android 1.1.58 (944), installed over the existing T575 application without
  clearing user data or pairing. S26U was not used for this verification.
- Final Gradle build: `testDebugUnitTest`, `assembleDebug` and
  `assembleDebugAndroidTest` passed in 14m 46s. JVM XML reports 3,551 tests,
  zero failures/errors and five existing skips across 509 suites; the ten new
  delivery-policy tests passed.
- Final memory device group: 33 passes, zero failures/skips, 80.436s. This covers
  eight outbox tests and 25 deletion-ledger, identity and asynchronous UI-work
  regression tests. It is not a foreground latency benchmark.
- Image, attachment, model/runtime timing and latency-journal regression group:
  22 passes, zero failures/skips, 12.353s. Missing-model timing tests do not prove
  successful local-model load performance.
- Persistent fixture `20260910-outbox-v1158`: preparation passed in 1.239s.
  After a physical reboot, boot ID changed from
  `a04da34f-f384-4ebd-a974-9b7d6cbd0b2d` to
  `09d64605-184b-4b1f-a2fe-5f9330d66b73`. Recovery passed in 0.501s with no
  skips. The original 200 deleted memories, deletion record, pending references
  and pre-acknowledgment test effect were not reseeded. Pending identities
  survived, the effect remained single, and acknowledgment completed. The
  test duration is not production startup/recovery latency.
- Repository guard, 73-library Android 16 KB audit and 24-library QNN package
  audit passed. QNN libraries total 221.68 MiB uncompressed.
- Final APK SHA-256:
  `403AA5947706BFDF02FF632132AA1EC612A1A78B29BCBE79DFD0487238048AE3`.
- Device update time: 2026-09-10 19:00:41; first installation time retained:
  2026-09-07 07:17:23.

Local evidence: `build/memory-retraction-outbox-final-build.log`,
`build/memory-retraction-outbox-device-final.log`,
`build/memory-retraction-outbox-regression-final.log`,
`build/memory-retraction-outbox-reboot-{prepare,recover}.log` and
`build/memory-retraction-outbox-final-{repo,16kb,qnn}.log`.
