# Android #3022: private knowledge projection scratch

Android reference: #3022, merge b0d5f6dffa9ee2667e9092223c21fabca9d877ac.
Incremental iOS parent: b602dc1063447c70a13952d75b81116a45162aa4 (#4607).
This branch retains the shared storage ancestry from #4596 and #4600-#4607;
the complete diff against main must be reviewed, not only this increment.

## Prepared-source export integration follow-up

The branch now merges updated #4607 at `d29e681d2`, including the newer
statistics admission, primary metadata/copy/compaction and prepared-source
chains. All of that shared ancestry remains part of the complete main diff,
not newly delivered #3022 work. The same formal PR/main base is retained;
no duplicate PR or dependency merge wait is introduced.

An actual exporter blocker was found: both bulk source groups and targeted
replacement headers omitted `sourceRevision`, while snapshot enumeration
rejects an empty revision. New bulk writes now compute the complete legacy
sorted-JSON/length-prefixed SHA-256 digest. Targeted writes compute the same
digest after normalization using encrypted staging with a separate indexed
identity collation, one decoded record at a time. No source-sized body array
is added to that path. Chunk-based observation/projection order is unchanged.
Canonical-equivalent but byte-distinct IDs get an explicit raw UTF-16 tie-break;
ordinary valid legacy revision encodings remain unchanged. Missing/corrupt
staged data aborts rather than yielding a partial completed digest.

Source enumeration now owns the shared committed-view adapter, original
lifecycle generation and physical retention lease. Header/body authentication,
strict keyset progression, integer timestamps, exact member count and explicit
ROW/DONE/errors remain checked, with scoped statement return on exceptions.
Each delivered record is checked before/after its callback. A source changed
before view admission rejects a stale group; a change after admission retains
the consistent original WAL/body snapshot and defers physical reclamation.

The writer retains its original native lifecycle generation through both
authenticated scratch scans, output writes and pre-publication checks. A
generation change after source enumeration, including during the second render
pass, cancels and removes the output stage without replacing the destination.
This remains cooperative checking, not hard preemption or protection against
an arbitrary mutation between the last check and filesystem replacement.

Seventeen new synthetic methods cover new bulk/target revisions, actual bridge
output/hash, stale-group rejection, replacement during snapshot callbacks,
lifecycle invalidation/retry, streamed identity-order digest equivalence,
missing staging rows, lifecycle loss during the second render pass, and the
legacy recovery/transaction cases below.
The complete scope has 302 authored methods (267 inherited, 18 original scratch
and these seventeen); none compiled or executed. Source guards compare complete
retained files outside the declared revision/export hooks against updated
#4607. Query-only validation now checks the actual shared view implementation.

## On-demand legacy revision recovery and transaction correction

Historical persisted headers with blank revisions are now resolved only when
their source is requested for export. The exact authenticated header and source
generation are captured, then the existing outside-writer preparation adapter
authenticates all source members into private encrypted staging. Exact count and
complete identity-ordered content digest are verified before a short canonical
transaction. Publication rechecks generation and the original header ciphertext,
then atomically updates only the encrypted header, bound preview and browse
revision. Bodies, source generation, permissions, timestamps, vector epoch/head
and source observation outbox are not rewritten. The global vector feed stamp's
browse revision does advance; this is not a claim that every feed stamp field is
unchanged. A previously prepared source replacement remains usable.

The projection spec resolves the revision before recording its generated index
entry, and does not prepare a legacy source after the write budget is exhausted.
Direct snapshot/export consumers use the same resolver. Corruption, membership
count mismatch, cancellation, a concurrent source change or header re-encryption
rejects publication, not a guessed digest or an automatic retry. Recovery does
not scan the entire library at startup. Preparation now owns a pure committed
view instead of triggering unrelated corpus-wide index repair through the generic
read helper. Missing Codable fields from arbitrary old schemas, crash-resumable
recovery jobs and a complete export backlog remain outside this increment.

A real nested SQLite transaction bug in the earlier targeted revision integration
is also corrected: normalization must finish its scratch mutation transaction
before identity ordering starts its own transactions. Digest ordering is allowed
only for finished staging; lifecycle checks bracket each decoded digest record.
New synthetic cases cover this ordering, legacy reopen and actual output/hash,
concurrent replacement, exact-ciphertext CAS, count mismatch, injected failure,
lifecycle invalidation/retry, prepared-generation/vector-ledger preservation and
unauthenticated headers. These are authored source fixtures, not native results.

## Implemented iOS boundary

The existing two-pass Markdown rendering remains; source enumeration is hardened
as described above.
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
fixtures (174 across that earlier review scope). They have not been compiled or run;
the integrated totals and remaining gaps are stated above.
JavaScript checks validate source contracts and retained surrounding code only.
No native compilation, XCTest, device acceptance, CI monitoring or IPA generation
is part of this increment. No Android performance measurements are transferred.

Long source snapshots, resumable full exports, candidate-list scaling and complete
cross-platform parity remain separate work. SQLite comparator lifetime and cache
semantics follow the [collation API](https://www.sqlite.org/c3ref/create_collation.html)
and [cache pragma](https://www.sqlite.org/pragma.html#pragma_cache_size); the
[SORT counter](https://www.sqlite.org/c3ref/c_stmtstatus_counter.html) is an operation
count, not a memory-bound proof.
