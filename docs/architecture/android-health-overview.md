# Android Health Overview

The Health Center uses one compact measurement list and a fixed bottom row
for photo, manual entry, file import, and device connection. The production
view does not include mock values or a health score.

## Read Contract

- The four pinned metrics are blood pressure, sleep duration, resting pulse,
  and steps. Other metrics join the list when their latest record compares
  outside an applicable range. Temperature and oxygen saturation remain in
  the catalog, not in the overview.
- Indexed latest-record queries exclude deleted rows, future measurements,
  and non-self observations. Recent means the last seven local calendar
  dates for most metrics and today for steps. A prior count is not shown as
  today's count. Each observed value includes time and source. Expanding the
  row exposes its saved revision and measurement history.
- Inline comparisons use the same record's reference or an applicable,
  confirmed target bound to that exact record revision. Each range shows
  its source and units. Color is paired with explicit text, and components
  such as systolic and diastolic pressure are compared separately. No
  ranges or goals are invented when none can be used.
- The measurement record center still exposes actionable OCR and table
  reviews. At most 30 ready-state import candidates are inspected by
  index. OCR links require a recognized page and either an unfinished
  review draft or no previously recorded observation for the original;
  deleting a saved measurement does not recreate a review. Table links
  require the current batch to be selecting a sheet, mapping, or ready for
  confirmation. This is a bounded shortcut, not a full unreviewed count.

## Presentation And Refresh

The longitudinal preview shows up to three confirmed due or overdue actions, or
the next scheduled action when none are due, and links to the existing review
and full agenda. It also previews up to three open concerns and their latest
recorded visit, if not cancelled. Follow-up rows open the exact journal rather
than another concern's journal. These are bounded previews, not total counts.
If an index is still being prepared or a bounded page cannot establish absence,
the overview points to the full list rather than claiming there are no actions.

Reads respect confirmed-measurement and profile permissions. The overview
checks source versions and ownership, and does not evaluate a concern, send
health information to a model, modify its plan or deliver a reminder.

Out-of-range rows appear first, newest first. That order is not a clinical
severity assignment. Revoking confirmed-measurement authorization clears
comparisons without deleting readings. Observations, privacy changes, and
local day rollover refresh the visible overview. The activity clears visible
data on stop and reloads after returning, preserving scroll when possible.
Summary reads and decryption stay off the UI thread.

## Verification

Version 0.1.7.30 (Android 1443) was built and cover-installed on Galaxy
Tab Active3 (SM-T575). The final focused suites passed 290 JVM tests, 252
non-visual device tests, and 46 native UI/lifecycle tests without skips.
The actual empty overview was inspected after the final install. Isolated
fixtures exercised recent, older, missing, pending review, completed
import, ordering, privacy revocation, and lifecycle states. No fixture
measurements were written to the production archive.
