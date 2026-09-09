# Resumable knowledge projection traversal

Android 1.1.23 replaces the repeated all-source enumeration introduced by the
uncapped 1.1.21 projection with a bounded, encrypted traversal checkpoint. This
addresses the 1,201-source correctness baseline which took 1,797,337 ms on SM-T575.

## Scheduling and memory

Each worker obtains at most one page of 50 source summaries. It visits sources
until its write budget is consumed or the page ends, persisting the exact last
visited keyset position. The next worker resumes after that position, including
when the write budget stops partway through a page. Deferred bodies are not read.
The existing write maximum remains 32 per worker; it is not a corpus/action cap.
Knowledge and non-knowledge projections share that write budget.

An unchanged corpus is also visited in bounded pages, rather than one long pass.
`remainingCount` now counts sources not yet inspected in the current traversal,
plus deferred non-knowledge writes. It does not assert that every remaining source
needs rewriting. The existing WorkManager continuation uses this nonzero count.
Completion clears the cursor so a subsequent synchronization can detect edits.

The edit scanner no longer decrypts every projection index just to inspect eight
notes. It pages storage keys, decrypts at most eight index entries, and advances an
encrypted key cursor after inspecting that page. Entries already marked modified
still advance the cursor, avoiding starvation of later notes. Its old numeric
offset is no longer used.

## Recovery and mutation

The encrypted checkpoint binds the vault namespace, source-database scope, corpus
revision, exact keyset position and visited count. A changed corpus revision or
invalid database scope resets the traversal; ordinary source-index checks avoid
rewriting unchanged notes. A final revision check prevents a mutation observed
during the last page from being reported as completed synchronization.

The file and its encrypted index are committed before the cursor advances. If a
process stops between the index and cursor writes, the current item is rechecked;
the matching index prevents a second file write. If a write fails before indexing,
the cursor does not skip it. This ordering is not atomic filesystem replacement
or a general exactly-once side-effect guarantee.

Projection worker entries are serialized within the App process, so event-driven,
explicit and continuation workers cannot race the same cursor/file writes. These
operations remain on the existing worker path, not on the UI thread. This is not
resource-level locking for the general Agent execution framework.

The checkpoint is not a plaintext corpus cache. Existing source privacy filtering,
exact source identity and conservative legacy-file adoption remain unchanged.
No ASR, QNN, model selection or transport behavior is changed.

## Acceptance scope

- Cursor JVM tests cover 1,201-source bounded traversal, unchanged pages, durable
  serialization, write-before-checkpoint interruption, corpus mutations before and
  during a page, namespace/database separation, zero budget and invalid state.
- The same 1,201-source real-device fixture now runs through the production cursor
  runner, retains close/reopen and all-file assertions, and additionally bounds
  source summary reads. Its unchanged final verification spans bounded pages.
- Device tests also cover index-before-checkpoint interruption, updating a source
  behind a persisted cursor and detecting user edits beyond the first eight notes.
- The existing complete-source, privacy, corruption, legacy identity, source paging
  and stable-identity cases remain in the device selection.

Remaining boundaries: SQL grouping/count still visits corpus metadata to obtain
each page; frequent concurrent corpus updates can repeatedly invalidate a pass.
This is not a durable per-source dirty-work queue or a million-source catalog.
One very large source's Markdown is still materialized. Candidate lookup during
edit detection and non-knowledge projection descriptors retain their existing list
APIs. Actual configured SAF-provider atomicity, cross-process vault writers,
ambiguous legacy-file reconciliation, learned reranking and broader Memory 2.0
acceptance remain unfinished.

## Measured SM-T575 projection comparison

Both versions used the same 1,201-source fixture, 39 write batches, knowledge-store
reopen, full file/index/body checks and final unchanged verification. Test databases
were isolated and regenerated with the same workload, not copied user data.

| Metric | 1.1.21 | Pre-merge cursor build (1.1.22) |
| --- | ---: | ---: |
| Timed projection fixture | 1,797,337 ms | 167,129 ms |
| Written sources/index entries | 1,201 | 1,201 |
| Write batches | 39 | 39 |
| First batch body reads | 12 | 12 |
| Unchanged verification body reads | 0 | 0 |
| Total source summary reads | Not logged | 3,093 |

The timed case is about 90.7% shorter in this single device comparison. It includes
repeated enumeration, writes, reopen and assertions, not just storage throughput.
It excludes WorkManager scheduling and a real configured SAF provider. The cursor
test also enforces at most 1,950 summary reads while writing the corpus, followed
by one bounded-page unchanged traversal. This is not a P95/P99 or million-source
performance guarantee.

The new interrupted-checkpoint case injects an exception after committing a real
file/index and then reopens the repositories. It does not kill the process or
reboot the tablet; those end-to-end recovery scenarios remain separate acceptance.

The complete pre-merge device selection passed all 24 tests in 501.730 seconds,
with no failures/ignored cases: 11 projection, seven source-pagination and six
stable-identity cases. The associated process crash buffer was empty.

Host verification: the 19 focused JVM tests passed; the full updated Android core
selection passed 92 tests in ten classes with no failures/skips (including those
19, not in addition to them). Four CI runner contract tests passed. Both APKs built,
73 AArch64 libraries passed 16 KB alignment, and 24 QNN libraries passed packaging.

Pre-merge experimental Android 1.1.22 (908) APK SHA-256 (not the final PR artifact):
`48094aad3d9df9d0bafd0f4f2610b68588598a8a23a4127bc1f1538dd6bd49a6`.

Main subsequently merged the unrelated artifact retry fix as 1.1.22. This branch
incorporates main `2da3b488c` and advances to 1.1.23; the final integrated artifact
is built and checked separately from the above pre-merge comparison.

### Final integrated 1.1.23 (909) verification

- Installed on SM-T575 without uninstalling or resetting application data.
- All 24 device tests passed in 509.986 seconds on the integrated APK.
- The same 1,201-source projection fixture completed in 162,215 ms with 39 write
  batches, 3,093 summary reads, 12 first-batch body reads and zero unchanged-pass
  body reads. Compared with the 1.1.21 baseline, elapsed time decreased by about
  91.0%. The single-workload and SAF-provider limitations above still apply.
- All 95 JVM tests passed, including the 19 focused projection tests and the three
  artifact retry tests added on main. These counts are inclusive, not additive.
- Four CI runner contract tests passed. Both APKs built successfully; all 73
  AArch64 libraries passed 16 KB alignment and all 24 QNN libraries passed the
  packaging check.

Final application APK SHA-256:
`ed0bbc9242167c1529a62297063991d25a7fc92ae7ce99b40625e7d74f68e2e3`.
