# Authoritative metadata in primary partitions

Android 1.1.118 moves newly written authoritative record headers out of the
catalog's `knowledge_items.header` value and into the same physical partition
and immutable entry as the complete encrypted record. The catalog stores a
69-character `khp1:` token instead. Catalog schema 17 prevents an older reader
from interpreting this token as damaged inline ciphertext.

## Integrity and commit boundary

The token contains the SHA-256 digest of the encrypted header, not plaintext
metadata. The authenticated primary reference binds that digest to the item,
partition and immutable entry. Resolution requires the catalog token, reference
digest and actual header digest to agree; the original AES-GCM record-header
envelope must also authenticate. Missing or damaged metadata fails closed. The
reader does not reconstruct a replacement authority from an otherwise readable
body when an external header was expected.

The header contains fixed-width index keys, content checksum, timestamp and
legacy chunk count. Variable-length title/source/access metadata already exists
in the complete record and authenticated derived source preview, so new headers
do not duplicate that preview. The encrypted structural header is bounded at
4 KiB without truncating user titles, source names or record content.

Body frames and the header row commit in one primary SQLite transaction with
DELETE/EXTRA before the catalog publishes either reference. Physical schema 2
adds a `headers` table. Existing schema-1 files remain readable and receive that
table in a committed schema transaction only when opened for writing.

## Relocation and recovery

Small-record compaction validates and copies the header before publishing the
new reference. Checkpointed large-record copies do the same after frame
verification and before catalog publication. An unpublished destination header
can be replayed after process death. Root tokens remain identical during a
physical relocation, preserving source revisions, preview fingerprints and
derived-vector revision identity. Retiring a body file also retires its headers.

## Existing records and remaining work

Existing inline headers remain authoritative and readable without an eager
rewrite. A normal logical update writes the new partitioned representation.
Background migration of untouched old headers is not delivered here: it must
preserve existing snapshot, source-preview and vector revision identities.

The root still owns keyed catalog indexes, source directory, derived preview
cache, FTS and vector-control metadata. This change is an actual partitioned
authority write/read path, not completion of the full catalog/FTS sharding plan.
No 100-million-record acceptance or universal sub-200 ms latency is claimed.

## Acceptance

`tools/dev/test-knowledge-primary-metadata.ps1` covers compact catalog tokens,
real encrypted headers, corruption/missing-data rejection, pointer substitution,
preview rebuilding, rollback, small and checkpointed relocation, schema-1
upgrades, legacy reads, source revision preservation and long user metadata.
Existing process-death and OS-reboot copy fixtures now carry encrypted headers
and require them to authenticate after every recovery check. The retained
catalog audit script reads only the explicitly named synthetic database after
instrumentation ends, verifies SQLite integrity, and requires 10,001 compact
header references with no orphan references. It never exports user databases.

### SM-T575 results, 2026-09-13

Android 1.1.118 (1004) was installed without uninstalling or resetting the app.
The final APK passed 15 metadata cases, 95 legacy cases, 55 reader/relocation
cases, seven durability cases and 97 source/backup/search cases. These suites
overlap and are not a count of unique tests. The JVM suite passed 3,836 tests
with five existing skips; 74 AArch64 libraries passed alignment checks, and
Repository Guard passed.

The first legacy run had one fixture failure: constructing an old v7 record
from a new header omitted the historically embedded source preview. The fixture
now reconstructs that historical field from its verified complete test record.
The assertion that source pagination does not load bodies was not weakened;
the three-case migration class and all 95 legacy cases passed on rerun.

All seven intentional copy-process deaths recovered with authenticated metadata.
A real device reboot recovered the 16-frame checkpoint and completed copying.
The test-local restoration took 179.958 ms; this excludes the operating-system
boot and instrumentation startup. Host wait for boot/storage readiness was
43.644 seconds, not 179.958 ms.

The existing 10,001-record corpus was updated through the normal source API
with variant `primary-metadata-v1`, without changing its IDs or count. Update
took 671,597 ms; reopening and checking every record took 104,040 ms. All records
used compact primary header references, the catalog passed `integrity_check`,
and no orphan references existed. Four physical partitions remained registered.

Retained compaction moved all 10,001 records in 1,253 bounded pages, retired four
old files, and preserved the complete encoded-record digest and logical source
revision across reopening. The full test took 309.073 seconds, including both
full-corpus verifications; maintenance itself took 90,570 ms. Physical bytes
changed from 20,295,680 to 12,300,288 before subsequent latency probes.

Two 300-operation runs measured public reads, individual durable upserts and
restores against those same short records. Writes include partition and catalog
commits. Models and observers were disabled, so these are not full UI or
semantic-retrieval measurements. Overall 598/600 operations were within 200 ms;
two reads took 260.037 and 238.653 ms. Upsert P95 was 115.931 and 113.567 ms;
public-read P95 was 25.170 and 20.798 ms. These observations do not guarantee
all operations or larger corpora meet 200 ms.

Compact metrics, failure history, recovery boundaries and APK hashes are in
[the evidence summary](evidence/knowledge-primary-metadata-20260913/summary.json).
