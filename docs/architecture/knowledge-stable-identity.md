# Knowledge identity and replay safety

Android 1.1.19 makes `AgentKnowledgeItem.id` the update identity of an individual
knowledge record. A title is a display label and search field, not a primary key.

## Previous failure

The single-item upsert used `item_key = ID OR title_key = kind + lowercase(title)`
to select and delete old rows. Saving a second same-named item could therefore
delete a different source, its access policy, encrypted chunks and vector rows.
The existing 1,201-record retention test used distinct titles and did not detect
this collision. Bulk `replaceSource` had separate source-scoped semantics and
was not evidence that individual upserts were safe.

## Contract

- A new nonblank ID creates a separate record, even if its title, kind or source
  matches another record.
- An existing ID updates only that record. Renaming it cannot delete another ID.
- An existing ID cannot be reassigned to another source by upsert. This matches
  the source-ownership check already enforced by `replaceSource`.
- An exact replay, after input normalization, does not rewrite encrypted rows,
  invalidate vector checkpoints, publish another mutation or request another
  semantic indexing job.
- A changed record still uses the normal atomic transaction, index invalidation,
  post-commit mutation event and background indexing path.
- Failed writes roll back. Blank IDs fail explicitly instead of sharing an empty
  identity key. Blank title/content retain their previous no-op behavior.

Callers intending to update a record must retain its ID. Reusing a title is not a
deduplication mechanism. Importers already generate IDs from source and ordinal.
Independent screen captures retain their separately generated identities.
The title index stays in place; no database migration or data reset is required.
Previously overwritten records cannot be reconstructed by this change alone.

## Validation scope

`KnowledgeIdentityDeviceTest` exercises the actual encrypted SQLite store:

1. Same titles across sources, independent access policy and FTS retrieval.
2. Case variants and renames within one source without deleting another ID.
3. Cross-source ID theft and blank IDs rejected without mutation events.
4. Twelve identical replays preserving an encrypted vector checkpoint exactly.
5. Injected SQLite failure rolling back an update and retaining a same-named peer.
6. 601 incremental, same-named sources retained after close/reopen and full export.

The replay test uses a deterministic four-dimensional encoder to isolate ledger
identity, not to claim neural-model quality or throughput. Existing real-model
lifecycle/hybrid tests cover that separate integration.

On SM-T575, the new two-source collision regression was first run against the
installed 1.1.18 (904) APK. It failed with `expected 2, actual 1`, establishing
that the test detects the old data-loss behavior. The 1.1.19 (905) APK was then
installed without uninstalling or clearing data. Its SHA-256 is
`f84a9ad109e17249c462ee53f70500711765da60c430b9af7ce05b03c02aec14`.
The focused JVM run passed 18 tests; the package audits passed all 73 arm64
16 KiB alignment checks and all 24 QNN manifest libraries. The device fixtures
use isolated database names and remove only their own data after each test.

The final installed 1.1.19 device run passed **40 tests in 548.697 seconds**:
6 identity regressions, 11 database regressions, 5 FTS regressions, 7 model
lifecycle regressions, 10 hybrid search regressions and 1 real BGE hybrid test.
This includes the 601 same-title upserts and the existing 1,201-record retention,
601-record backup, large encrypted Unicode item, migration and rollback cases.
The elapsed time is suite duration, not a claim about single-query or UI latency.

Reproduce after building/installing the app and test APK (the model suites require
the pinned external BGE test fixture documented in the semantic model lifecycle):

```text
adb -s <authorized-device> shell am instrument -w -e class com.galaxyssi.chat.KnowledgeIdentityDeviceTest,com.galaxyssi.chat.AgentKnowledgeDatabaseDeviceTest,com.galaxyssi.chat.AgentKnowledgeFtsDeviceTest,com.galaxyssi.chat.KnowledgeModelLifecycleDeviceTest,com.galaxyssi.chat.KnowledgeHybridSearchDeviceTest,com.galaxyssi.chat.KnowledgeHybridNeuralDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

This is a data-loss and replay fix within Memory 2.0. It does not implement
semantic conflict resolution, learned reranking, forgetting policy, source-list
pagination or the remaining full-backup memory improvements.
