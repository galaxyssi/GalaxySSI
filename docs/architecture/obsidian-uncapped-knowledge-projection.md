# Uncapped Android knowledge projection

Android 1.1.21 replaces Obsidian's independent `list(limit = 500)` input with
the knowledge source pager. This is a local, explicitly configured vault export;
it does not upload knowledge or enable a cloud provider.

## Enumeration and incremental work

The source iterator holds at most one page of 50 display summaries. A projection
descriptor captures a source reference and revision, not the decrypted records.
The batch checks the encrypted projection index before invoking the content
loader. For new-format records, unchanged and user-modified notes do not load source bodies. Sources
deferred by the existing 12-write default/32-write maximum per worker run also do
not invoke the complete source body loader. Legacy records without an encrypted
display preview retain the source pager's compatibility fallback: one representative
body may be read per group to obtain metadata, without rewriting that ciphertext.
The zero-body-read tests use new-format records, not legacy headers.
The write budget is a per-run scheduling quantum, not a total
corpus limit: subsequent runs continue until `remainingCount` reaches zero.

The iterator still visits metadata for all sources to compute the exact remaining
count. It does not stop after 500 records or split one source at that boundary.
Consequently, draining a new corpus over bounded write batches revisits unchanged
metadata in later batches. This is bounded-memory enumeration, not an incremental
export work queue or a large-corpus latency guarantee. A durable cursor/work queue
is still needed to eliminate repeated full metadata passes.
Filtered blank content counts as considered, avoiding an endless remaining-work
loop for sources which the existing privacy policy excludes.

## Source consistency

Source IDs now use domain-separated SHA-256 over the exact, untruncated source or
local-item identity. The previous semantic `GlobalAgentText.stableKey` normalizes
every HTTP URL to `<url>`, causing unrelated web sources to share one projection
index entry. Semantic normalization is not suitable for persistent identity.

Legacy index adoption requires the existing note's bounded front matter to match
both the old managed ID and the exact source. A full streaming file hash also
protects edits which the background scan has not yet noticed. A matched managed
file retains its path; its new index and removal of the matched old index commit
atomically after writing. A colliding legacy index is never adopted by another
source. Ambiguous or unindexed legacy files are left untouched rather than guessed
or deleted; reconciling those files may still require user review.

Each descriptor hashes length-framed item keys and encrypted headers in stable
item-key order. The authenticated header contains the full record body hash and
its source/policy metadata. A same-timestamp, same-chunk-count content update now
changes the projection revision; the former update-time/count fingerprint could
miss it. Exact record replay leaves the revision unchanged.

Before reading bodies, the source revision is checked again inside the same
knowledge database transaction as the complete read. A changed source raises a
retryable synchronization error rather than writing a file under an obsolete
revision. Changing a different source does not invalidate this source snapshot.
Full multi-page enumeration still detects corpus mutations through pager cursors.
The cognition worker routes a nonblank projection error to its existing
WorkManager retry path instead of treating the failed projection as success.

All source chunks are authenticated and ordered by chunk index, then stable ID.
Existing sensitive-body and metadata filtering, Markdown formatting, local-note
identity, explicit vault setup and user-edit protection remain in place. The
production file writer saves an index entry only after its output stream closes
successfully and clears its transient UTF-8 byte array after use.
An already indexed source retains its original relative path when its title or
the representative display chunk changes, preventing duplicate files on upgrade.
If a DocumentFile provider appends an extension, a newly created empty file is
renamed to the requested exact filename before writing, keeping the path index
consistent. Failed renaming cleans up only that newly created empty file.

## Boundaries

This removes the full-corpus body allocation and 500-record truncation. Rendering
one selected source still materializes that source's records and Markdown string;
very large individual documents are not yet fully streaming. Non-knowledge
projection descriptors and edit-scan indexes still use their existing list APIs.
SAF writes still use the existing direct target-file flow, so provider-level
atomic replacement and interrupted-write recovery remain separate work.

This milestone does not complete learned reranking, sharded ANN, streaming backup,
memory conflict/forgetting policies or the wider cross-device reliability goal.

## Tests

- JVM batch tests: lazy body reads, 1,201 descriptors, repeated bounded runs,
  user-edit protection, privacy-filtered completion and write failures.
- Device tests: real encrypted knowledge storage and the production file writer
  through a temporary file-backed DocumentFile vault; 1,201 sources across runs
  and knowledge-store reopen, 601 chunks in one source, exact replay, unchanged
  timestamps, stale snapshots, private metadata, local same-title notes and
  corrupt ciphertext.
- Fixtures use unique test database namespaces and vault directories; no existing
  vault, pairing, model configuration or user records are cleared.
- The core CI Android suite now explicitly includes the projection batch and
  privacy JVM tests. The runner contract verifies both filters remain present.

## Build and host verification

- Android 1.1.21 (907) and its instrumentation APK built successfully.
- The two focused JVM classes passed 11 tests. The complete updated core Android
  selection then passed 84 tests in nine classes, with no failures or skips. The
  11 focused tests are included in that total, not 11 additional distinct tests.
- Four Node regression-runner contract tests passed. Repository checks passed
  after updating the worktree to main `18251a54f`.
- All 73 AArch64 libraries passed 16 KB alignment. All 24 required QNN libraries
  passed the package audit. ASR and model configuration were not changed.
- The APK was installed over the existing SM-T575 app. Its original installation
  date was preserved; the connected SM-G9880 was not operated on.

APK SHA-256:
`e576323d710985dccd78cc9264fb46f65e9473f89a84fb90f3a5feed81620ffc`.

## SM-T575 device verification

The initial 19-test device run failed three projection cases. Actual execution
exposed URL aliasing in the semantic identity helper and automatic `.md` extension
appending by file-backed DocumentFile. The corrected implementation was reinstalled
and the entire expanded selection was rerun, not only the failing examples.

- All 21 tests passed in 2,131.546 seconds with no ignored cases: eight projection,
  seven source-pagination and six stable-identity tests.
- The projection case retained all 1,201 source notes and distinct index entries
  over 39 bounded write rounds, including a knowledge-store close/reopen. All
  expected bodies were present exactly once. The first round read 12 source bodies;
  a subsequent unchanged full pass read zero bodies.
- That complete projection case took 1,797,337 ms (about 29 minutes 57 seconds).
  Its timer includes repeated enumeration, file writes, reopen, full-file assertions
  and the final unchanged pass. This is a correctness/stress baseline, not a passing
  performance target. Repeated full metadata scans need the incremental queue/cursor
  improvement described above.
- The source pager traversed 1,201 entries across 25 pages in 25,677 ms with no body
  reads in this run. This slower result supersedes any assumption that the previous
  single 2,363 ms traversal establishes a reliable P95. The 601 same-title identity
  case preserved all entries across writes and reopen in 63,692 ms.
- The current test-process crash buffer was empty. Test vault files were removed
  by their own fixture cleanup; no existing user vault or user records were cleared.
- The final main update to `5bceb2f7a` only changed Desktop/backend/docs files;
  the tested Android source and APK were unchanged.
