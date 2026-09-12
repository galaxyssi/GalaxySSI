# Streaming knowledge source replacement

## Scope

Android source replacement accepts a one-shot sequence. The document importer
uses that path instead of constructing another list of knowledge records.
Existing list callers delegate to the same implementation. This does not make
the document parser itself streaming: its existing input and extraction limits
remain unchanged.

## Storage boundary

1. Filter invalid source/title/content records and stage the first valid record
   for each stable ID in encrypted SQLite rows. A keyed unique index replaces
   the growing in-memory deduplication set. Reject blank IDs.
2. Start the canonical writer transaction. Read the old source through its
   source index in 64-row rowid pages, authenticating and staging one body at a
   time. Retain only the oldest policy, using the existing item-key tie-break.
3. Authenticate incoming identities and reject cross-source ownership before
   any canonical mutation.
4. Apply inherited permissions and summary normalization, then write changed
   items and delete removed items in the same transaction. Exact replays do not
   rewrite the canonical rows or invalidate derived vectors.
5. After commit, publish at most one source-level observation through a synchronous
   staging view. Close and remove this call's encrypted temporary database.

The incoming producer is consumed once, before reserving the canonical writer.
A producer failure, invalid ID, ownership collision, corrupt previous body,
corrupt staged body, or SQL failure does not commit a partial source. Staging
failure is not converted into an empty-source deletion.

## Observation semantics

The production publisher does not materialize old/new body lists. Encrypted
external runs order records by chunk index and ID, and a streaming fold retains
the existing content fingerprint, policy fingerprint, summary, tags, item count,
event identity, and retractions. Disabled global processing exits before this
sort/fold, without enabling that feature or contacting a model.

Internal fixture constructors retain an explicit list-callback adapter. They are
not the public production construction path. Callback views are synchronous and
must not escape their staging lifetime.

The fold preserves the legacy exact ACL union and its normalization. Distinct
allowed-agent IDs still use a metadata set; an adversarial source with millions
of different ACL entries is **not** a fixed-heap case. Body retention and ACL
metadata scalability are separate claims.

## Limits and remaining work

- This is not a 100-million-record acceptance result or a universal 200 ms
  write guarantee. A bulk replacement remains O(source size) and holds one
  canonical writer transaction after staging. Large WAL growth and writer
  latency still require generation-based publication in a future phase.
- The largest individual record is still decoded as a String. The heap bound
  is not independent of record size; there is no whole-source JSON array on the
  production replacement path.
- Temporary staging is encrypted, but crash-orphan staging cleanup follows the
  existing backup staging lifecycle. This patch does not claim a new durable
  outbox: process death after canonical commit and before observation enqueue
  can still leave an unpublished event. Publication errors do not roll back an
  already committed source.
- Legacy whole-store JSON adapters and other corpus-wide mutations are outside
  this patch. Canonical metadata remains in the existing WAL database.
- Existing payload, retrieval, backup, source paging, and permission tests must
  pass alongside the new replacement cases. The scale fixture is retained and
  checked record-by-record, rather than using metadata-only rows.

## Verification

Run `tools/dev/test-knowledge-source-streaming.ps1` only on the designated
SM-T575 device. It rejects other serials/models, preserves production data, and
requires all 106 cases including the 10,001-body replacement and reopen case.
Each class's instrumentation output is saved separately with bounded size.
The full host JVM run reported 3,816 tests: 3,811 passed, five existing skips,
and zero failures/errors. The ten new source-observation equivalence cases all passed.

The SM-T575 scale case completed on Android 1.1.105 (991), retaining 10,001
real encrypted bodies. It replaced the same database's contents, reopened it,
and authenticated every resulting record without materializing the full set.

| Measured operation | Elapsed |
| --- | ---: |
| Initial 10,001-record replacement, including staging and observation | 370,103 ms |
| Replace the existing source with 10,001 changed records | 659,246 ms |
| Reopen, count, check removed IDs, and verify every remaining body | 232,684 ms |

The producer's sampled Java heap high-water value was 69,248,690 bytes. This is
not a continuous process/PSS peak measurement. The canonical SQLite file was
68,341,760 bytes; that figure does not include WAL, payload, or temporary files.
Do not divide the bulk duration by the row count and present that as per-call
latency or a P95/P99 result. Long writer occupancy remains an explicit gap.

Retained fixture: `test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db`.
Bounded evidence lives in `evidence/knowledge-source-streaming-20260912/`.
All 106 device regressions passed in 2,093.028 seconds. An independent check of
the saved instrumentation statuses confirmed exactly 106 passes and no failures.
The 1,201-record selective retrieval case decrypted one body in 46 ms; 100 hot
queries reported P50/P95/P99 of 37/45/66 ms. These are selective retrieval
results, not 100-million-record or cold-start measurements. A separate
concurrent encrypted-append helper took 330 ms, exceeding the 200 ms target.

The verified APK SHA-256 is
`7f0afbd92de66c68d7140e2506dfa95b1085957312e463789ca40962ea1c662e`.
The test APK SHA-256 is
`7022d251ed7eb9550a7f0895b57bb1bfdd32f61f0280e1ea02363835bec1d58a`.
Repository checks and all 74 Android AArch64 16 KB alignment checks passed.
No physical reboot or new source-specific process-death injection was performed
in this run; reopen and transactional fault injection are not equivalent to those.
