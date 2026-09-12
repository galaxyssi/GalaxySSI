# Indexed source revisions and bounded read snapshots

## Scope

Android 1.1.97 adds knowledge schema 10. This removes the full-source encrypted-header scan from the unchanged-source check used by Obsidian projection and exposes a closeable source iterator. It is a step toward the large-memory goal, not proof of 100-million-record capacity or sub-200-ms full-document export.

## Durable freshness

`knowledge_source_revision_state` stores a database epoch and monotonic mutation sequence. `knowledge_source_revisions` stores the latest sequence for each opaque source group. SQLite triggers update both in the same transaction as the canonical row mutation. Exact application-level replays do not rewrite rows. A changed non-head chunk with an unchanged timestamp still advances its source token. Unrelated source updates do not invalidate that token.

The migration creates empty revision tables and triggers without scanning or rewriting existing content. An existing source starts at revision zero until its first mutation. A deleted source has an absent token; recreation receives a new sequence. Empty group entries are removed rather than accumulating tombstones. Missing state, ignored revision writes and integer overflow fail the source transaction.

Tokens are freshness hints, not cryptographic content authentication or anti-rollback proofs. Canonical encrypted headers, chunks, checksums and identity checks remain authoritative for returned content. Restoring a complete old database can also restore old tokens; secure rollback detection requires a separate design.

## Source iterator

`KnowledgeSourceExport.snapshot()` opens a separate query-only WAL connection, pins a revision and checks source-directory readiness. Its cache target is 2 MiB and mmap is disabled. Initialization holds the owner monitor only briefly; consumption does not hold the live writer monitor.

Iteration uses the existing `knowledge_source_members_order(group_key, sort_updated, item_key)` covering index with a tuple keyset cursor and pages of at most 64 keys. It does not create a new whole-corpus index during migration or use OFFSET pagination. The iterator authenticates one item at a time and checks source identity, sort metadata and emitted count. Callers must close the snapshot, including after partial consumption or cancellation, using `use`.

A source change before snapshot creation rejects the stale token. A concurrent committed change after creation is not visible to the pinned snapshot. A subsequent projection sees the new source version. Source snapshots are single-consumer resources, not shared cross-thread SQLite connections.

## Remaining scale work

- `KnowledgeSourceExport.items()` intentionally preserves the existing complete List and chunk-order contract for the Markdown renderer. Whole-note String construction and export still need a streaming renderer and an authenticated chunk-order index or external ordering mechanism.
- Long readers can pin WAL history and increase disk usage. A fixed per-connection SQLite cache does not bound total WAL storage or the memory required for one unusually large item.
- Source bulk access edits and replacement still materialize complete source members and need atomic scalable semantics, not independently committed partial permission changes.
- Canonical knowledge data still uses one SQLite database. Shard lifecycle, routing, compaction, cross-shard recovery and hundred-million-record disk-vector acceptance remain outstanding.
- Existing legacy whole-JSON backup entry points must not be confused with the newer streaming backup path.

## Verification plan

Focused device tests cover isolated source versions, exact replay, same-timestamp non-head edits, blank-source IDs, deletion/recreation/moves, schema-nine migration, rollback, ignored trigger writes, sequence overflow, paging boundaries, extreme timestamps, indexed query plans, partial closure, concurrent writer progress, stale snapshot rejection and content corruption.

The explicit scale fixture contains 10,001 real encrypted items in one source, unlike the earlier 10,001-source fixture. Evidence includes ciphertext invariance, bounded page size, every returned identity, 200 indexed revision reads and 200 unrelated encrypted writes. A separate opt-in test kills the process with an uncommitted mutation and verifies the previous committed revision and all rows in a new process.

Measured results and artifact identifiers are added only after the corresponding device runs complete. These storage tests do not prove UI latency, all-model performance, full Run Kernel adoption or long-cycle Agent DAG acceptance.

## Verified results, 2026-09-12

Android 1.1.96 (982) was installed with data preserved on SM-T575. Final source, paging, backup, migration and preview regressions passed all 60 tests in 210.320 seconds. The same retained 10,001-member corpus then passed full traversal, identity, count, order and ciphertext-invariance assertions in a 136.402-second run, without reseeding a smaller corpus.

| Measurement | Result |
| --- | ---: |
| Previous full-header digest, P95 of 20 samples | 176.895 ms |
| Indexed revision lookup, P95 of 200 samples | 8.173 ms |
| Indexed revision lookup, P99 / maximum | 11.263 / 12.323 ms |
| Unrelated encrypted write, P95 of 200 samples | 71.445 ms |
| Encrypted write, P99 / maximum | 85.176 / 98.553 ms |
| Schema-nine migration plus first token | 37.402 ms |
| Full 10,001-row authenticated traversal | 119.520 seconds |
| Largest key page | 64 |

Every sampled indexed lookup and write was under 200 ms. Queries and writes alternate sequentially; this is not a concurrent saturation or cold-device benchmark. The separate concurrent-writer test verifies progress during a pinned snapshot. All encrypted canonical rows remained byte-for-byte unchanged after the scale test.

The final package also passed a new-process recovery run: 65 committed source rows and their token survived intentional process termination while an additional row and token were uncommitted. Verification passed in 1.663 seconds. Test fixture cleanup is separate from recovery acceptance.

Build verification: 3,765 JVM tests across 539 suites, zero failures/errors, five pre-existing skips; all 74 Android AArch64 libraries passed the 16-KiB alignment gate. The earlier pre-hardening package additionally passed all 11 Obsidian projection regressions, including 1,201 sources and a 601-chunk source. That 11-test suite is not represented as a rerun on the final two-guard hardening change.

See [raw scale evidence](evidence/android-source-revisions-20260912/README.md) for artifact hashes, sample files and reproduction scope. The full goal remains incomplete.

After these runs, the PR's release metadata was advanced to 1.1.97 (983) because concurrent PR #3019 also used 1.1.96 (982). No Android implementation changed with that reservation. The measured and installed APK remains the explicitly identified 1.1.96 test artifact; a 1.1.97 installation is not claimed here.
