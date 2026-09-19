# Public research evidence audit

## Scope

Version 1.2.11 adds the task-local `research_audit` tool to Android conversational
cloud providers and Desktop Codex dynamic tools. The shared research policy also
applies to other remote agents, but their native tool registration is not added
by this change. The tool records public findings and evidence, never private
chain-of-thought. It performs no network requests or independent model calls.

The submitted snapshot contains scope, entity candidates, claims and coverage
facets. Each claim carries source URLs, exact quoted passages and support,
contradiction or context relationships. Model-generated fields are explicitly
distinguished from host-observed provenance checks.

## Guarantees and boundaries

- Source/quote checks use previously observed tool output in this task only.
  A quote match has a passage hash and local excerpt offset; it is not a
  semantic-entailment check or full-document reading certificate.
- Unsupported entity decisions become pending. Exclusion without an explicit
  positive-mismatch basis cannot become a confirmed exclusion. Even an anchored
  decision is a model assessment, not independently verified identity.
- Claims tied to pending, excluded or missing entities cannot stay supported.
  Submitted counterevidence remains visible and marks the claim disputed; an
  unobserved counter-source is not falsely upgraded to verified evidence.
- Coverage queries are compared with observed query receipts. Planned queries
  cannot inflate those counters. Completeness always remains not established;
  database/language/date/type coverage is a model-described checklist, not proof
  that every relevant record has been found.
- Known DOI URL aliases and PubMed URL variants share a record key. Other mirrors
  are not automatically merged by title or authors. Record count does not mean
  independent evidence count; DOI-to-PMID cross-database resolution is future work.
- Counters cover host-observed activity only. Native Codex opened-page receipts
  expose no quote text, so they cannot pass quote matching unless readable evidence
  is available from the existing host fetch tools. The host does not launch a
  duplicate search loop to manufacture evidence or replace native research.
- Snapshot limits: 40 entities, 80 material claims, 40 coverage facets and eight
  references per row, at most 160,000 characters. Invalid/oversized submissions
  fail without replacing the previous snapshot. This is a compact material-claim
  ledger, not a full arbitrary-size research corpus.
- Source observations are bounded at 20,000 URLs, 4,096 unique queries and eight
  million excerpt characters. Truncation is explicit. Simple weather/image/news
  lookups do not require an audit call.

## Execution and recovery

Android's streaming loop requests one bounded public-audit pass for investigations
that have source evidence but no submitted ledger. Existing tool and synthesis
limits still apply. The audit tool is also executable by the legacy conversation
loops. It does not modify the source disclosure UI.

Android stores audit arguments/results in the existing encrypted model-loop journal.
On recovery it replays observed evidence and then audit submissions in order. Final
quality metadata includes the audit. Existing cancellation and task isolation remain.

Desktop Codex registers the same JSON schema as a dynamic tool and stores the audit
report in execution checkpoint metadata and final research quality metadata. Native
Codex tool history remains the authority on resumed native turns. Automatic host
reconstruction of all audit quote observations after a Desktop process restart is
not implemented; missing observations must be re-established, never fabricated.

## Quality review

Shared lint detects narrowly phrased exhaustive-publication claims and exclusions
based solely on dates/career discontinuity. Android now invokes its existing bounded
repair path for quality risks instead of only logging the report. Regex lint does
not establish that an unflagged answer is true. Pending candidates and coverage gaps
are valid findings, not reasons to discard an otherwise useful partial report.

## Acceptance

Validation on the 1.2.11 source build: Android compilation and 136 focused/regression
unit tests passed, with zero failures or skipped tests. Desktop's 153 research,
dynamic-tool, routing, concurrency and recovery tests passed. No APK was installed,
no running Desktop was replaced, and no real paid research task was submitted in
this change. These are implementation checks, not a factual-accuracy benchmark.

Tests cover real versus invented source/quote references, unresolved identity,
exclusion basis, counterevidence, query receipts, identifier aliases, malformed
snapshots, atomic rejection, task isolation and Android checkpoint replay. Desktop
tests exercise dynamic tool registration, task routing, checkpoint events and closed
task rejection. Real research-quality comparisons with human-reviewed bibliographies
and broader investigations remain a separate acceptance stage. No claim of perfect
recall, independent truth verification, or a decade-long performance guarantee is made.
