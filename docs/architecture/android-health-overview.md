# Android Health Overview

The Health Center overview shows four key metrics, record freshness, and
real attention items. The first-use state offers photo, manual entry, and
file import without requiring a device or a provider. There is no sample
profile, synthetic result, or health score.

## Read Contract

- The key metrics are blood pressure, sleep duration, resting pulse, and
  steps. Temperature and oxygen saturation also contribute to the coverage
  count and are labeled explicitly when missing.
- Indexed latest-record queries exclude deleted rows, future measurements,
  and non-self observations. Recent means the last seven local calendar
  dates for most metrics and today for steps. A prior count is not shown as
  today's count. Each observed value includes time and source and opens its
  saved revision.
- With confirmed-metric authorization, the sleep card can show the average
  of usable daily values across the last seven completed dates. The read
  shares the weekly report calculation and is recorded in encrypted access
  history. Revoking authorization clears derived views, not the person's
  right to view their own underlying measurements.
- The overview consumes existing pending sleep reminders only if their
  date, zone, current threshold, rule version, and metric revision match.
  It never creates, delivers, or reopens an alert. Snoozed or handled
  episodes are not presented as new attention items.
- The most recent actionable OCR and table-review items are shown separately
  from measurements. At most 30 ready-state import candidates are inspected
  by index. OCR links require a recognized page and either an unfinished
  review draft or no previously recorded observation for the original;
  deleting a saved measurement does not recreate a review. Table links
  require the current batch to be selecting a sheet, mapping, or ready for
  confirmation. This is a bounded shortcut, not a full unreviewed count.

## Presentation And Refresh

The preference can put health changes first, review first, or sort by
recency. The stored value is only an ordering choice, not a clinical
severity assignment. Unknown/failed sections are separate from an empty
result. Observations, reminder changes, import states, privacy changes, and
local day rollover refresh the visible overview. The activity clears
visible data on stop and reloads after returning, preserving scroll when
possible. Summary reads and decryption stay off the UI thread.

## Verification

Version 0.1.7.30 (Android 1443) was built and cover-installed on Galaxy
Tab Active3 (SM-T575). The final focused suites passed 290 JVM tests, 252
non-visual device tests, and 46 native UI/lifecycle tests without skips.
The actual empty overview was inspected after the final install. Isolated
fixtures exercised recent, older, missing, pending review, completed
import, ordering, privacy revocation, and lifecycle states. No fixture
measurements were written to the production archive.
