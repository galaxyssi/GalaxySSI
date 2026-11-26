# Android #3022: private knowledge projection scratch

Android reference: #3022, merge b0d5f6dffa9ee2667e9092223c21fabca9d877ac.
Incremental iOS parent: b602dc1063447c70a13952d75b81116a45162aa4 (#4607).
This branch retains the shared storage ancestry from #4596 and #4600-#4607;
the complete diff against main must be reviewed, not only this increment.

## Implemented iOS boundary

The existing source-snapshot enumeration and two-pass Markdown rendering remain.
This increment replaces its persistent-key scratch database with a private job
directory, fresh in-memory CryptoKit AES-GCM key, encrypted sort metadata and
encrypted item bodies. Production scratch does not persist the key or expose a
plaintext body digest. The existing injected cipher override is fixture-only.
Clearing key references is not a claim of RAM zeroization.

SQLite performs external B-tree ordering rather than reproducing Android's
512 KiB runs and fan-in 16. The requested 512 KiB pager cache, disabled mmap and
file-backed temporary storage are read back. This is a soft cache target, not a
total memory limit or performance result. Each individual item is still decoded
and encoded in memory. Authenticated keys compare chunk index then raw UTF-16
identity, matching Kotlin tie order rather than the old iOS ID-digest tie order.
Malformed keys retain a stable comparator classification and poison the job.

Each scan checks authenticated key/body binding, expected row count, strictly
increasing logical keys and explicit SQLite ROW/DONE/error results. Unexpected
SQL sorting is rejected. Both passes validate; first-pass authentication precedes
destination staging. A second-pass failure discards the stage without replacing
the existing destination. Closing from a scan callback defers native disposal
until statement finalization and stops further delivery.

Cross-process advisory leases protect live jobs from orphan cleanup. Cleanup
checks the anchored directory identity, allowed filenames, regular-file type
and link count before deleting any child; unknown contents and links are left
alone. Old flat scratch namespaces are deliberately not swept. This is not a
defense against a malicious process already able to mutate the app container.

Edited-file hashes cover the complete file with 8 KiB reads; only the bounded
candidate prefix is retained. Decoding remains strict UTF-8, unlike Android's
replacement decoding. Prefix limits now count UTF-16 units without splitting a
surrogate pair, not Swift grapheme clusters. Legacy ownership uses bounded
front matter plus a full-file hash. Existing unindexed files are preserved.

Knowledge publication checks the expected generated hash before preparation,
then rechecks the baseline inside NSFileCoordinator before atomic replacement.
This protects cooperating writers, not arbitrary uncoordinated filesystem
mutation between checking and replacement. Final Markdown staging is plaintext
with complete file protection set before writing; process death may leave that
protected output stage. It is not an encrypted scratch file or crash-proof
output-stage cleanup guarantee. Non-knowledge projection adapters are unchanged.

## Scope and verification

Eighteen synthetic XCTest methods are authored, including real bridge output,
late corruption, interrupted scans, active/orphan leases, Unicode boundaries,
destination edits and reentrant close. They supplement 156 inherited authored
fixtures (174 across this shared scope). They have not been compiled or run.
JavaScript checks validate source contracts and retained surrounding code only.
No native compilation, XCTest, device acceptance, CI monitoring or IPA generation
is part of this increment. No Android performance measurements are transferred.

Long source snapshots, resumable full exports, candidate-list scaling and complete
cross-platform parity remain separate work. SQLite comparator lifetime and cache
semantics follow the [collation API](https://www.sqlite.org/c3ref/create_collation.html)
and [cache pragma](https://www.sqlite.org/pragma.html#pragma_cache_size); the
[SORT counter](https://www.sqlite.org/c3ref/c_stmtstatus_counter.html) is an operation
count, not a memory-bound proof.
