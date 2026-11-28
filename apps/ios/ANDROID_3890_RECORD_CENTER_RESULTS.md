# Android #3890: record center entries, results and review queue

Reference: Android merge `7c98635fab8b5c0e27ec0f19c95b94acf0432a61`.
Baseline: main `c6bad3465c673dfb2dcecb23b095185c129c7447`.

The existing iOS record center already provides camera, manual entry, file import,
device/source navigation, pending OCR review, table review/history, recent records,
originals and metric catalog destinations. This is not a replacement of that port
or a claim of complete screen parity. Android's recent row uses
`healthDisplayValue(record.draft)`; iOS still used only the optional numeric field.

## Change

- Reuse the metric catalog's display semantics: reported raw notation first,
  otherwise locale-formatted numeric value; include blood pressure's diastolic
  component and the saved unit only when nonempty.
- Comparisons, ranges and qualitative results are not coerced to exact numbers.
- The result-only change retains grouping, ordering, pagination, drafts,
  navigation, scene clearing, notifications, storage and confirmation gates.
- The result-only change adds no strings, permissions, model calls or network traffic.

## Entry layout follow-up

The same PR also replaces the four plain entry rows with the Android entry order:
camera (orange), manual (green), files (blue), device/source (violet). Retain the
existing destinations and callbacks, including the direct Files entry action.
Each tile has a decorative 36-point icon, title and subtitle, 12-point padding,
8-point radius and a minimum height that can grow with content. Use a two-column
grid where space permits; the 325-point threshold scales with the body text size
and the available width is remeasured on resize. Narrow or large-type layouts use
one column, without text truncation. Use plain button behavior to keep each action
independent within the List row. Add stable action accessibility identifiers and
combine each title/subtitle; decorative icons are hidden from accessibility.

Seven new Chinese resource entries and English fallbacks match Android's entry
titles and subtitles. The earlier result-only change introduced no strings; this
layout extension does. No runtime permissions or model/network traffic are added.

## Mixed pending reviews

Android's overview repository combines OCR/table review jobs ordered by creation
time before limiting the record-center list. iOS previously showed only report
groups, sorted by arbitrary UUID, and exposed tables only behind a history link.

- Retain exact original-ID/digest grouping, but sort report groups newest-first.
  Prefer the exact ID/digest recognition job's creation time. For legacy groups,
  fall back to the matching original's import date, then the latest saved review
  staging date; undated groups sort last. Ignore nonfinite dates. Do not substitute
  the clinical measurement time or another digest's job date.
- Combine report groups and saved table reviews into one namespaced queue, sort
  descending by timestamp and stable identity, then apply the existing page limit.
  Table-only queues no longer show the empty-review message. Manual draft resume
  remains a separate entry and the general table history destination remains.
- A table row passes both the exact saved draft ID and version to the existing
  table importer. Its existing fresh-version and confirmation checks remain
  unchanged; opening the row does not confirm/import it. Report rows retain the
  unavailable/changed-source state instead of binding a replacement original.
- Display available import/review timestamps. No storage schema, ingestion,
  permissions, confirmation, original bytes or notification policies change.

Three authored Swift fixture methods cover interleaved tables/reports before
pagination, job time priority over UUID/import/staging/clinical times, legacy and
nonfinite dates, foreign-digest jobs, table-only queues, exact table version,
source-digest separation and deterministic tie ordering. They are not executed.

## Validation limits

`node apps/ios/tools/check-health-record-center-results.cjs` checks the exact
approved source deltas, catalog formatting agreement, Android reference, seven
localized resources and twenty-eight synthetic negative source mutations. The
authored fixture block is checked without executing it and previous fixtures are
retained. These checks do not execute Swift or prove
rendered output. Native compilation, localized numbers, comparator/range and
qualitative rows, blood pressure, grid measurement, Dynamic Type, VoiceOver,
independent action gestures, pixel parity and device navigation remain unverified.
Live review queue ordering, stale table navigation and process/lifecycle behavior
also remain unverified. This is not completion of the entire Android record center
or the overall Android-to-iOS parity backlog.
No native tests, CI inspection or IPA build is performed for this follow-up.
