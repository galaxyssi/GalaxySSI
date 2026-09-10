# Incremental personal-memory writes

Android 1.1.62 (948). This follows PR #2988's indexed flag operations and is
another partial step of the [100M+ design](scalable-memory-100m.md).

## Actual Agent write path

`EncryptedAgentMemoryStore.remember` now resolves candidates through the
personal-memory lookup index and applies a target-only mutation. It no longer
calls `loadItems`, `trimHistory` or `saveItems` for every new fact or repeated
piece of evidence. Observation extraction receives the actual before/after
delta, preserving duplicate, conflict, privacy and provenance behavior.

Input passes through the existing canonical codec before lookup, not only
before persistence. Otherwise a decorated key whose second normalization
removes trailing whitespace could create a different lookup identity from its
stored record. Writes retain the codec's existing payload bounds and reject
damaged old rows instead of replacing them while leaving stale membership.

For keyed memories, the lookup identity is kind + scope type + scope ID +
normalized memory key. For unkeyed memories it additionally includes the
case-folded value, because different unkeyed values are not conflicts. The
actual duplicate decision still uses `equals(ignoreCase = true)`. Folding uses
simple code-point case conversion rather than locale-sensitive or
multi-character expansion; targeted JVM and Android tests cover sigma, Turkish
I, long S, sharp S and related cases.

Historical superseded records are not candidate-index members. They remain in
authoritative encrypted rows and are not silently deleted to make retrieval
or ingestion fast. The former shared 1,000-item current/history retention budget
has been removed from personal-memory mutation. Explicit deletion still applies
its existing lineage and deletion-barrier policies.

## Encrypted lookup and atomic commit

- Each lookup membership is a separate row, not a growing JSON array of IDs.
- The key contains an index generation, an Android Keystore HMAC-SHA256 digest
  of a length-framed identity and the existing opaque ID hash. Raw memory keys,
  scope IDs and unkeyed values do not appear in SQLite storage keys.
- Membership values remain AES-GCM encrypted with database/key associated data.
  A separate non-exportable HMAC key is deleted by the existing private-data
  reset path. An encrypted metadata stamp detects an unavailable/replaced key
  instead of treating a different token namespace as an empty search result.
- The index reveals equality/membership patterns and record counts. It is not
  equivalent to fully encrypted SQLCipher index pages, nor does it hide all
  access patterns. Native encrypted-page/block storage remains part of the
  larger architecture, not something delivered by this change.
- Record bodies, membership changes, active/total counts, ordering allocation
  and revision commit in the same SQLite transaction. ID collisions and stale
  target records fail before overwriting another memory. Duplicate evidence
  addition and revision allocation are checked against integer overflow.
- The process-wide memory lock continues to coordinate in-process writers.
  This does not add multi-process writer coordination or a new power-loss
  durability guarantee beyond the current SQLite configuration.

Lookup reads use 128-key pages. A new ordinary identity reads only its matching
bucket, not all existing memories. A genuine conflict group still requires its
matching candidates: a huge same-key group can be expensive, and no count cap
or silent candidate truncation has been introduced to conceal that cost.

## Migration and legacy callers

Stores with existing v3 rows but no lookup marker are backfilled through
128-row pages. A fresh generation and its metadata switch commit together;
failed validation or writes leave the original rows and marker unchanged.
Stale generations are retired transactionally. Metadata counts are a consistency
check during migration, not an ongoing full-index integrity audit on every
lookup. Arbitrary out-of-band deletion of a valid index row is not detected by
a constant-time metadata read.

Remaining full-replacement callers must maintain lookup membership in their
own transaction. Unchanged memberships must not be rebuilt merely because a
flag, confidence or access timestamp changed. Identity changes, history state
changes, scope rebinds, deletions and restores must update the affected entries.
This requirement is covered by explicit regression tests.

Physical row positions remain stable for survivors; incremental inserts allocate
a new position. Public snapshots and recent views retain their timestamp/priority
ordering, including backdated input. The internal row listing is not a public
timestamp-sorted query API.

Legacy whole-collection recall, snapshot/recent, edit, delete, conflict
resolution and backup import/export are still unfinished scaling work. Some of
those callers continue holding the shared lock for a long time. The v3 legacy
JSON import also remains a one-time whole-array parser; replacing it and the
whole-JSON backup format with framed streaming is still required.

## Validation contract

Tests use isolated T575 fixture databases, never the user's memory or pairing
data. Coverage includes target-only writes despite unrelated corruption,
unchanged ciphertext, live conflicts, namespace/privacy isolation, Unicode,
paged migration, migration failure, write rollback, ID collisions, damaged
lookup pointers/key stamps, legacy membership refresh, history retention and
concurrent duplicate evidence.

The ingestion benchmark inserts 100 actual new records and merges 100 duplicate
observations into datasets starting at 1,201 and 10,001 stored rows. It checks
physical body/index cardinalities separately from cached metadata. Report
P50/P95/P99, maximum and all samples at or above 100ms. These are warm
same-process repository calls with observation publication disabled in fixtures,
not full Agent, UI, cold-start, embedding or semantic-search measurements.

The JVM suite completed with 3,586 tests, zero failures/errors and five existing
skips. Debug application and instrumentation APKs built successfully. Repository,
16KiB native alignment (73 libraries) and QNN package (24 libraries) checks passed.
The final application SHA-256 is
`EF92EBB3D6AF42916E663579F525C61D2F86AFE52C121D9960629492D1F3775A`.
T575 received this APK through an in-place update; its original installation
date and app data were retained. No other connected device was modified.

### Preliminary trial (not final acceptance)

An earlier APK passed the first 16 instrumentation tests before the final two
canonical-payload/corruption cases were added. Its ingestion measurements are
retained, including the slow sample; they must not be discarded because a later
run happens to be faster.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | New record | 38.88 | 47.17 | 53.90 | 56.05 | 0/100 |
| 1,201 | Duplicate evidence | 49.72 | 55.78 | 62.08 | 65.80 | 0/100 |
| 10,001 | New record | 39.12 | 64.44 | 69.31 | 72.42 | 0/100 |
| 10,001 | Duplicate evidence | 50.12 | 82.98 | 91.81 | 100.63 | 1/100 |

### Final APK acceptance

All 18 incremental-write instrumentation tests passed on SM-T575 in 238.042s.
The final-run process was 23000; measurements were emitted at 21:40:31 and
21:43:06 on 2026-09-10. Each operation has 100 observations per starting size.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | New record | 40.79 | 66.35 | 71.30 | 93.47 | 0/100 |
| 1,201 | Duplicate evidence | 52.77 | 85.06 | 91.10 | 105.62 | 1/100 |
| 10,001 | New record | 60.04 | 79.38 | 86.33 | 92.45 | 0/100 |
| 10,001 | Duplicate evidence | 75.57 | 94.34 | 100.49 | 102.59 | 3/100 |

These timings include synchronous repository calls through transaction return,
not only queue admission. They exclude the disabled observation publisher and
fixture setup. They do not prove physical power-loss durability or end-to-end
Agent response latency. New rows finish below 100ms in this sample, but four
duplicate calls across the two sizes do not. Therefore the absolute latency
requirement has not passed, even though all reported P95 values are below 100ms.

The same final APK also passed all 51 existing memory regression tests in
469.109s and all 22 image/attachment/runtime timing regression tests in 19.608s.
Combined device coverage is 91 passed, zero failed and zero skipped. The memory
group includes indexed point operations, row storage, the retraction outbox,
deletion/backup barriers, UI-thread dispatch and namespace isolation. The image
group verifies existing compression/original-attachment and timing behavior;
it is not a new ASR/QNN inference-performance acceptance run.

Local raw logs are under `build/` as
`personal-memory-incremental-acceptance-{build,device,timings}.log` and
`personal-memory-incremental-preliminary-timings.log`, with the regression groups
in `personal-memory-incremental-memory-regression.log` and
`personal-memory-incremental-regression.log`.
The 100M+ engine and unconditional sub-100ms requirement remain unverified.
