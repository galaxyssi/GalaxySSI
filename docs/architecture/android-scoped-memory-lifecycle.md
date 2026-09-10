# Android scoped personal-memory lifecycle

## Invariant

Personal-memory mutation identity is `(kind, scope, exact scopeId, key)`.
Scope IDs are opaque and case-sensitive. Existing key normalization remains
unchanged. A different scope type or ID must not participate in de-duplication,
conflict resolution, same-key deletion, or version-lineage deletion.

This applies to both `InMemoryAgentMemoryStore` and `EncryptedAgentMemoryStore`.
The existing scope types are global, conversation, application, contact,
workspace, and device. This change does not introduce a new agent scope or
change model routing, ASR, QNN, or the knowledge-store retrieval pipeline.

Query-based recall and deletion require a positive lexical match before ranking
bonuses are considered. Previously the delete predicate used a ranking score
that was positive even for unrelated content because it included recency and
evidence. Ranking bonuses remain available for relevant recall candidates, but
cannot select unrelated rows for disclosure or deletion. Query deletion remains
an explicitly global matching operation; selected-item deletion is scope-bound.

## Existing data

- A legacy conflict group can contain several mutation identities. On load it
  is partitioned by identity. Each multi-row partition receives a deterministic
  group ID; a single-row partition becomes active again.
- Values, IDs, source, timestamps, privacy, confidence, and version metadata are
  retained. Superseded rows remain history.
- Normalization happens inside the decoded-snapshot cache and on writes, not
  as a database rewrite on every UI read. The next mutation persists the repair.
- Resolving a conflict additionally checks the selected row's identity, even
  when the caller supplies a valid group ID belonging to another scope.
- Version-lineage traversal only visits existing rows in the selected kind and
  scope. It follows renamed keys and handles cycles in linear time without
  following missing or foreign parent IDs.

The fix cannot reconstruct records that an earlier version already merged or
deleted. It prevents new cross-scope mutations and repairs separable conflicts
whose original records are still present.

## Causal deletion

New deletion fingerprints use a `scope-v2:` prefix and length-framed identity
fields, preserving the exact scope ID. Existing unversioned deletion hashes
remain recognized during restore so previously deleted data is not resurrected.
Those old hashes already discarded scope-ID case and whitespace distinctions;
their original distinctions cannot be reconstructed from the hash alone.

The existing internal observation-suppression flag now also suppresses immediate
retraction publication. Deletion tombstones are still persisted. Normal stores
continue publishing retractions. Isolated device tests suppress observations and
never schedule global/evolution work or contact a provider.

## Verification scope

`AgentMemoryIdentityTest` covers all scope types, exact IDs, memory kinds,
same-scope duplicate/conflict behavior, editing, deletion, foreign lineage,
cycles, 10,000-node lineage traversal, mixed legacy conflicts, idempotent repair,
private-memory preservation, and old/new deletion fingerprints.

`AgentMemoryIdentityDeviceTest` uses unique database paths on the authorized
device. It exercises actual encrypted persistence, new store instances,
raw legacy encrypted records, resolution, deletion tombstones, duplicate
evidence, and 1,201 active namespaces. It does not modify user memories,
contacts, credentials, or installed models. New store instances in the same
instrumentation process are not claimed as device-reboot verification.

## Verified build (2026-09-10)

- Android 1.1.56 (942), tested on SM-T575 `R52R90282TY`.
- Final Gradle build: `testDebugUnitTest`, `assembleDebug`, and
  `assembleDebugAndroidTest` passed in 12m 8s.
- JVM: 3,531 tests across 507 suites, zero failures/errors, five skips.
  The new identity suite has 18 passing tests with no skips.
- Device: eight memory lifecycle tests passed in 1.672s, no skips, including
  unrelated-query recall/deletion rejection and matching Chinese content.
- Device regression: 22 image preparation, original attachment, action timing,
  model timing, and timing journal tests passed in 12.349s, no skips.
  Missing-model Binder tests do not prove successful model-load performance.
- Repository guard, 73-library Android 16 KB audit, and 24-library QNN package
  audit passed. The QNN libraries total 221.68 MiB uncompressed.
- APK SHA-256:
  `238D989DD36466401C225050A12853BC1DD61BAFB774DEB994A8817B1C774B14`.
- Update installed at device time 2026-09-10 17:07:28; original installation time
  2026-09-07 07:17:23 was preserved. Launcher reported `Status: ok`, cold startup
  `WaitTime: 1103ms`. This one startup is not a P95 performance result or visual
  acceptance behind the system lock screen.

Local evidence: `build/memory-identity-final-build.log`,
`build/memory-identity-device.log`, `build/memory-identity-regression.log`,
`build/memory-identity-16kb.log`, and `build/memory-identity-qnn.log`.

## Remaining Memory 2.0 work

This is mutation isolation, not completion of Memory 2.0. Neural reranking,
complete retrieval authorization, conflict/forgetting lifecycle acceptance,
crash-atomic deletion, and durable uncapped deletion retention were separate
work at the 1.1.56 acceptance point. That release retained at most 2,000
tombstones and had per-record array limits. The subsequent storage transaction,
retention, migration and backup changes are documented in
[Durable personal-memory deletion](android-durable-memory-deletion.md).
The separate knowledge store's vector/FTS implementation is unchanged.
