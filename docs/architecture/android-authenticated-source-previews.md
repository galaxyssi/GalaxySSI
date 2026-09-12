# Authenticated source previews

Android 1.1.95 (code 981) follows the merged PR #3014. Full-corpus paired
measurements, real process-death recovery, 138 shared device regressions and an
additional permission-snapshot test passed on SM-T575. Latest-main integration
also passed full compilation/JVM tests, focused security checks, the complete
paired scale test and real process-death recovery. This is not completion of the 100M+, Run Kernel,
tracing or ordinary Agent Loop DAG goals.

## Measured reason

On SM-T575, the previous phase read all 10,001 retained encrypted sources in
201 pages. The complete authenticated 50-group page had P95 916.665 ms.
An independent five-pass component profile measured indexed SQL seek around
1.04 ms on average, versus 251.96 ms for 50 header AEAD operations and
190.10 ms for 50 identity HMAC operations. Repeating original header decryption
and identity derivation on every visit dominates the remaining page cost.

## On-disk representation

Schema 9 adds `knowledge_source_previews`, keyed by the existing opaque item ID.
It contains a 32-byte fingerprint and an AES-256-GCM binary envelope. No title,
source URL, logical item ID or access policy is stored there in plaintext.
There is no fixed retained-record limit and no decrypted corpus cache in RAM.

The fingerprint covers length-framed item ID, title key, source key, timestamp
and the complete original encrypted header. AEAD associated data binds the
fingerprint and opaque item ID to this preview format. A domain-separated key
derived through the existing Keystore HMAC key also binds the database name.
The original source header/body encryption, opaque IDs and vector identities
are unchanged.

Only the canonical source writer or an original header read that has passed
existing AEAD and identity checks can publish a preview. Fast reads authenticate
the preview against the current fingerprint, and pass the authenticated source
key to the source directory identity check. They do not trust an unverified
SQL label in place of the original source identity.

Source writes and previews commit together. Updates of relevant source columns
invalidate previews through a trigger; deletion cascades through a foreign key.
The writer snapshots caller-owned permission lists before encoding the body,
header and preview, so all three representations use the same policy.
Preview-only reads/writes do not advance the source browse revision. Changed
policies and representative-source deletion therefore cannot reuse stale
metadata or accidentally invalidate otherwise stable page cursors.

Missing legacy previews are generated on demand after full original validation.
A mismatched fingerprint or invalid envelope fails explicitly, rather than
displaying an unauthenticated result or silently accepting a corrupt cache.
An explicit repair path for corrupt derived previews is not added in this phase.

## Key lifetime

One database operation derives one preview key and can authenticate all its
page entries in software. Nested operations on that database share the scope.
The owned mutable key bytes are overwritten when the outer operation exits,
including error paths. Long-running operations replace the scope after 30
seconds on the next use. There is no static plaintext-key cache for previews.

JCA provider-internal key copies are discarded, not claimed to be manually
wiped. Temporary plaintext byte buffers are wiped; returned UI metadata remains
subject to the existing runtime plaintext lifecycle. No ASR, QNN, local model,
chat-history cipher or global memory setting is changed.

## Acceptance and remaining work

After integrating main `4ea021860`, the same retained 10,001 encrypted sources
were read again in three complete passes,
each with 201 pages of at most 50 groups. Each pass closes/reopens the database
before starting and again after page 100. All source titles, identities, order,
access policies and uniqueness are checked. The original encrypted header/body
fingerprint is unchanged; no body is decoded by these page reads.

| Pass | Preview hits / misses | Page P50 | Page P95 | Page P99 | Maximum |
| --- | --- | --- | --- | --- | --- |
| Build missing legacy previews | 0 / 10,001 | 544.307 ms | 816.803 ms | 852.819 ms | 893.675 ms |
| Ready previews after reopen | 10,001 / 0 | 23.822 ms | 35.268 ms | 41.984 ms | 73.938 ms |
| Ready previews, repeated full traversal | 10,001 / 0 | 23.411 ms | 31.647 ms | 36.923 ms | 38.927 ms |

Both ready passes satisfy the explicit P95 <200 ms gate. All 402 ready pages
were below 200 ms in this run. The legacy pass does not meet that target; it
still performs original Keystore authentication and writes previews on demand.
The previous 1.1.94 complete-page P95 was 916.665 ms on the same retained corpus.
These are storage-operation timings, not UI or 100M-capacity measurements.

An explicit process-death test commits 65 sources/previews, writes a 66th pair
without committing and terminates its own process. A different process verifies
65 surviving pairs, unchanged source ciphertext, 65 preview hits, no cache misses
or body reads, and no retained operation key. Recovery verification took 259 ms
inside the instrumentation test, excluding process startup. This does not claim
whole-device or Run Kernel recovery acceptance.

Raw page CSVs, reproduction steps and verification scope are in
[the evidence directory](evidence/android-source-previews-20260912/README.md).

This change does not synchronously materialize all legacy previews during open.
Their first read still pays original authentication plus preview creation.
Background/generational preparation, source sharding, remaining whole-source
membership/export APIs and full-scale NDK retrieval acceptance remain open.
