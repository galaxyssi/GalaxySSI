# Task-aware capability recall

Research assignments can discover previously saved procedures, workflow methods,
tool releases, capability channels, retained/rejected lessons and failure experiences
without paging through unrelated innovation records by hand.

## Production flow

1. A new dispatch searches using an excerpt of its assignment and original goal.
   The query, exact result references and continuation cursor are saved in its
   existing durable goal contract. Recovery keeps this snapshot instead of silently
   replacing it with later records.
2. The member can call `collaboration_recall` or the phone-native equivalent with
   `mode=capabilities`, a focused `query` and optional `cursor`. Android direct-cloud
   models and Desktop Codex use the same phone-owned search implementation.
3. Search returns exact version/hash references, matching terms and short excerpts.
   The member reads originals through `mode=workspace`, inspects evidence,
   applicability and counterexamples, and selects, adapts or rejects a method.
4. Actual reuse still goes through existing `procedure_use`, workflow, tool-release
   and capability-channel admission. Search does not install skills, start work,
   change permissions, mark goals complete or certify capability improvement.

## Retrieval and scope

- Normalization and English/Chinese tokenization reuse `AgentKnowledgeTextAnalyzer`.
  This is lexical retrieval, not semantic understanding, cross-language translation
  or a guarantee of complete conceptual recall. Agents can reformulate searches in
  different languages or inspect the full evolution directory.
- Results are ranked within each page, not globally. At most 100 index entries are
  inspected and 12 matches returned per call. These are transport/work bounds, not
  a limit on available history: `next_cursor` continues the scan, including after an
  empty result page. No matching result is discarded when a page fills.
- Cursors bind the query and member/dependency scope. This is an explicitly live
  directory scan, not a frozen global snapshot. Concurrent team publications do not
  force pagination to restart; a fresh query discovers additions or revisions behind
  the cursor. Exact original records remain readable through normal scoped recall;
  an earlier search result is not an adoption grant.
- Blind same-round work and other groups remain inaccessible. No personal memory,
  private conversation or other group's knowledge is automatically shared.
- Historical method records remain inspectable. Their reported state is explicitly
  not proof they are current or applicable; reuse admission checks exact lineage.

## Verification limits

Local tests cover bilingual retrieval, matches beyond the first directory page,
empty-page continuation, scope/recovery, stale-method rejection and passing a found
procedure into the real work-binding path. Bridge tests cover the authenticated
originating-phone route. They do not establish autonomous agent adoption, better
task quality, novel invention, long-term retention or multi-agent superiority.
Those require separate real-task measurements with appropriate comparison groups.
