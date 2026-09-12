# Streaming knowledge projection

## Scope

The Android knowledge-to-Obsidian production path prepares and writes one source
without collecting all source members, joining their bodies into one String, or
allocating a UTF-8 array for the entire generated note. Other projections, such
as conversation transcripts and plans, retain their existing String adapters.
This is a step toward large-scale memory, not acceptance of 100 million records.

## Ordering and snapshot ownership

`KnowledgeSourceExport.forEachOrdered` holds one read-only WAL snapshot. It
authenticates members through the existing 64-key page reader and emits only
`(chunkIndex, id)` ordering records. The live writer monitor is not held during
the traversal. Ordered records resolve bodies through that same snapshot, not
the live connection. Updates committed later cannot mix into an export.

`KnowledgeExternalOrder` limits estimated ordering metadata to 512 KiB per run
and merge fan-in to 16. A carry hierarchy keeps run descriptors logarithmic in
the number of records. It preserves the previous integer/UTF-16 String ordering,
including equal chunk indexes. An individually oversized ID is permitted; the
bound is the run budget plus the largest individual identity, not a new item
count limit. These are algorithmic buffer bounds, not a 512 KiB process-RSS claim.

## Encrypted scratch

Runs and the prepared body use the existing Tink AES-GCM-HKDF streaming primitive
with 64 KiB encrypted segments and a fresh random 256-bit job key. No job key or
plaintext source ID/body is persisted. Associated data binds each file to its
random job/file identity. Framed sorted runs validate ordering, record count,
explicit termination, and authenticated EOF.

Parent and job file locks serialize directory creation and orphan cleanup while
preserving active jobs, including owners in another process. An in-process
ownership set avoids opening a second descriptor for a live
job's lock. This follows the [FileLock platform warning](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/channels/FileLock.html)
about closing another channel potentially releasing locks on that file. Completion
and failure delete scratch files. A killed process leaves encrypted scratch with
no persisted decryption key; a later job reclaims it. Java/library-owned key and
String copies cannot be guaranteed physically zeroed; owned copy buffers are
cleared and the primitive reference is discarded on close.

## Rendering and failure behavior

The renderer retains only the first safe title, maximum update timestamp, first
16 distinct tags, a bounded privacy-boundary window, and one decrypted item at a
time. It preserves per-item filtering and whole-body redaction when a sensitive
expression spans the fixed blank-line separator. Body hashing occurs while the
body is staged; the final header uses that digest. Final output hashing covers
the actual header, body, and trailing newline bytes written to the provider.

The source is fully authenticated and the body prepared before the destination
is opened. A corrupt later member therefore cannot truncate a previously
projected note or advance its index. SAF providers do not uniformly offer atomic
replacement: destination write failures can still leave a partial external file.
The index is not advanced after such a failure. This change does not claim an
atomic external-vault transaction.

Edit detection decodes and hashes the entire note with fixed buffers while
retaining only the existing candidate-prefix limit. Its UTF-8 replacement and
hash behavior match the previous `readText()` implementation, including malformed
input. Candidate listing itself remains an existing separate scaling boundary.

## Costs and remaining work

Changed sources require two authenticated body passes, plus encrypted ordering
and staging I/O. Unchanged revisions still skip body rendering entirely. A full
source export is necessarily linear in source bytes and is not covered by the
sub-200ms point-query/write latency target. Long snapshots can retain WAL pages
while writers continue; resumable export checkpoints and WAL-pressure handling
remain future work. Individual item decoding still materializes one item.

## Verified acceptance

App 1.1.98 (984) was installed in place on SM-T575. Final verification passed:

- Full JVM suite: 3,779 tests, 541 suites, zero failures/errors, five existing skips.
- Ten focused JVM tests cover multi-level ordering, oversized identities,
  malformed/truncated records, encrypted file substitution, cleanup, interruption,
  bounded prefixes, and UTF-8 hashing.
- Fourteen device projection regressions passed in 216.331 seconds, including
  1,201 sources, 601 ordered chunks, legacy ownership, user edits, late corruption,
  stale revisions, failure replay, and byte-for-byte rendering equivalence.
- The retained 10,001-member encrypted source exported completely in 277.768
  seconds. Its original ciphertext fingerprint remained unchanged; the complete
  output matched the independently generated expected hash and survived store
  reopen. This is slower than a single body traversal because it authenticates
  bodies twice. No latency improvement for full-source export is claimed.
- Repository guard and 16 KiB alignment checks for 74 AArch64 libraries passed.

[Evidence and artifact hashes](evidence/android-streaming-projection-20260912/README.md)
record the tested bytes. No 100M capacity, process-RSS bound, UI latency,
other-provider, or cross-device recovery claim follows from this fixture.
