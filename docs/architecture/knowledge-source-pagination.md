# Knowledge source pagination

Android 1.1.20 removes the 500-item input cap from the knowledge source page.
The page now requests at most 50 source groups and offers previous/next navigation.
Navigation uses the existing arrow assets with 48 dp touch targets, tooltips and
localized accessibility labels; it replaces the page rather than accumulating rows.
The complete source count comes from SQL metadata, not the number of loaded rows.
The obsolete list-only `sourceGroups` facade was removed so callers cannot mistake
a first page for the entire collection. Control Center uses the complete count.

## Source identity and ordering

Nonblank source values group by their existing keyed source index. Local records
without a source group by stable item identity, not by title. Thus two same-named
local notes remain separately manageable. Group size is computed over the entire
database even when a source contains more than 500 chunks.

Groups sort by latest update descending and keyed group identity ascending. A
keyset cursor carries that pair, a database-specific scope and the knowledge
mutation revision. Numeric cursor comparisons explicitly cast bound parameters
to integers because SQLite aggregate expressions do not inherit column affinity.

Schema 4 adds a revision counter, INSERT/UPDATE/DELETE triggers on knowledge rows,
and a source/recent-record index. Changes to FTS or vector tables do not invalidate
the cursor. Knowledge mutations invalidate it; the UI restarts from the first page
instead of silently skipping or duplicating moving rows. Reopening the same
database preserves an otherwise valid cursor. Cursors cannot cross databases.

## Encrypted display summaries

New writes put display metadata in the existing authenticated encrypted header:
identity, title, source, policies, selected agents and update time. Source listing
decrypts only one representative header per visible group, never every member's
body or ID set. The representative's identity, source and timestamp are checked
against the keyed row metadata. Plaintext titles and paths are not added to SQL
indexes or the revision table.

Legacy rows remain readable without bulk rewriting. For a legacy representative
whose header has no preview, listing reads that one record through the existing
authenticated body reader. It does not rewrite its ciphertext or invalidate its
existing vector revision. Consequently first-page body reads on older databases
can be up to the page size; new-row tests must not be presented as a zero-body-read
claim for all legacy data.

The source page no longer builds the complete Mobile Agent runtime snapshot.
Queries and source permission changes run off the UI thread. Callback anchors
discard results after navigation to another page.

## Access editing and remaining boundaries

Page rows carry a source reference rather than eagerly collecting all item IDs.
Only an explicit permission edit resolves the current membership, reading header
metadata in batches of 64, then calls the existing atomic access update. This
includes all source members, not just the visible page or first 500 records.
The existing access-update implementation still materializes its changed records;
making very large permission edits streaming and reconciling concurrent membership
changes remain separate work. Pagination is not a claim that every knowledge
operation has bounded total memory.

The SQL grouping/count operation still scans keyed metadata across the corpus;
this is not a materialized source catalog or a million-source latency guarantee.
At the 1.1.20 milestone, Obsidian projection still had its separate 500-item read
cap. The [1.1.21 follow-up](obsidian-uncapped-knowledge-projection.md) removes that
cap through lazy source projection. Full backup export still materializes an
array, and learned reranking/sharded ANN remain unfinished.

## Acceptance coverage

`KnowledgeSourcePagingDeviceTest` covers 1,201 source traversal with tied dates,
bounded display decryption, 601-member source counts and access changes, local
same-title identities, stale cursors, exact replay/vector work, cross-database
cursor rejection, close/reopen, schema-3 legacy headers and corrupt data.

`KnowledgeSourcePagingUiDeviceTest` is explicitly opt-in via
`-e knowledgeSourcesUi true`. It inserts 55 named temporary records into the real
knowledge store, opens the normal knowledge page, checks 50/5/50 records through
next/previous controls, captures the second page and deletes only its own IDs in
`finally`. It does not uninstall, reset or re-pair the app.

## T575 verification

The September 9, 2026 SM-T575 run traversed 1,201 sources across 25 pages in
2,363 ms, with 1,201 summary decryptions and zero body decryptions for new-format
records. This is one complete-traversal measurement, not a P95 latency gate.
The 601-member source test changed both the first and last member's access policy
without changing an unrelated source. Schema-3 upgrade checks preserved both the
original header ciphertext and a previously completed vector's ciphertext.

Verification completed:

- 59 instrumented tests passed in 831.988 seconds: source pagination, encrypted
  database, FTS5, stable identity, model lifecycle, hybrid search, real neural
  retrieval and vector ledger. These ran before the final arrow-only UI polish.
- The final APK passed the opt-in production UI test in 20.381 seconds, including
  a rendered second-page screenshot and the 50/5/50 traversal assertions.
- 18 focused JVM tests passed on the final build: token search, embedding chunking
  and hybrid ranking.
- Both APKs built successfully; 73 native libraries passed 16 KB alignment and
  all 24 required QNN libraries passed the package audit. Repository checks passed.
- Android 1.1.20 (906) was installed over the existing T575 app without resetting
  its data. The production model selection and downloaded model were retained.

Final debug APK SHA-256:
`c75368da65787c6ca7d6487c8b2141ce022a2102988587a03fe0acafef5490b4`.

These results do not complete the overall Memory 2.0, full-device chaos or
end-to-end performance goals. The remaining boundaries above still apply.
