# Balanced news highlights

## Reference and scope

The design is informed by [Horizon](https://github.com/Thysrael/Horizon/tree/cdd95f8e881673057e3e201717836da4b8e2e0e7),
especially its separate collection, duplicate filtering, balanced selection and
enrichment stages. See its [balanced digest selection](https://github.com/Thysrael/Horizon/blob/cdd95f8e881673057e3e201717836da4b8e2e0e7/src/orchestrator.py)
and [profile scoring rubric](https://github.com/Thysrael/Horizon/blob/cdd95f8e881673057e3e201717836da4b8e2e0e7/profiles/tech-news/analysis.md).
This is an independent Android implementation, not a bundled Horizon runtime,
copied Python implementation, or a claim of equivalent AI editorial analysis.

## Reading behavior

The existing news menu adds **Highlights** alongside All, Unread and Saved.
All remains the default and retains the entire archive, full-text search,
Chinese bodies, source links, original images and illustrated knowledge reader.
Highlights uses the same expandable article cards and twenty-row incremental
reading pages, with a shortlist of at most thirty articles. It is not a storage,
collection, Agent-action or subscription-count limit.

The shortlist only uses actually published articles associated with at least one
enabled subscription. News is drawn from the previous seven days using the
original publication date, or collection time when that date is unknown.
Evergreen educational material does not acquire a fabricated news date and is
not discarded solely for age. Future-dated news beyond clock tolerance is not
selected. Existing non-news proactive messages remain available in All.

Selection considers existing importance, news versus evergreen material, dates
and stable identity. It visits the least represented enabled interests first,
assigns multi-interest articles to an available interest without duplicating
them, and balances actual publisher domains rather than RSS display labels.
The per-source and per-interest quotas are at least three, increasing when few
sources or subscriptions are available. This prevents volume alone from
dominating a varied archive without imposing a three-item ceiling on a reader
who follows only one source. Display remains chronological within the selected
set and uses the existing stable reading snapshot.

Only long, same-day identical headlines are folded in Highlights. Normalization
handles Unicode width, case, spacing and terminal punctuation, but preserves
versions, digits, negation and meaningful punctuation such as C++. Short generic
headings and different-day updates remain separate. This is deliberately not
semantic event deduplication. Every original article remains in All and search;
no bodies, source evidence, read markers or saved records are merged or deleted.

Reading a highlight only marks that original article read. It does not mark
hidden articles read, mark a source verified, or claim AI-assessed quality.
Read/unread changes do not affect shortlist membership. New arrivals do not
move an active reader, replace expanded text, or reset the saved scroll anchor.

## Performance and failure boundaries

The existing background reader loader joins public article metadata and indexed
subscription membership in batches of 300 IDs. It does not load document JSON,
full bodies, images, decrypted chat history, or run an additional model request.
The selector normalizes and sorts candidates once and performs at most thirty
selection passes. The final shortlist and light metadata are transient inbox
projections, not new persistent copies of public content.

A cold start restoring Highlights waits for the complete existing inbox load,
rather than presenting a falsely representative latest-only preview. Restored
reading keys and expansion state still use the existing reader state store.
No schema migration, reset, new foreground service, polling loop or private-data
transfer is introduced.

AI importance scoring, semantic story clusters, researched background,
community discussions and generated impact analysis are not implemented by
this change. Those require separate provenance, model-failure, cost and
factuality validation rather than relabeling local heuristics as AI analysis.

## Verification

Unit regressions exercise volume imbalance, sparse sources, overlapping
subscriptions, conservative duplicate handling, dates, deterministic ties,
read-state invariance, preserved archive pagination and a 10,000-candidate case.
Instrumentation tests exercise actual SQLite metadata joins, publisher-domain
normalization, disabled topics, unpublished rows, read-only behavior, and 1,205
records across the SQL parameter boundary. The menu regression includes the new
action and its single selected check. Instrumentation tests require a connected
device; compilation alone does not establish real-device acceptance.
