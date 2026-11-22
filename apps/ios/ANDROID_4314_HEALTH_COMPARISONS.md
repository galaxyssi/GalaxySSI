# Android #4314: Health activity and measurement comparisons

Source: https://github.com/galaxyssi/GalaxySSI/pull/4314
Android merge: `e2bf99432f61f6658e98f545d6072ac8a7b9ccc8`

## Implementation Scope

This change maps Android #4314's activity history, import/report selection,
two-group measurement comparison and source-aware trend behavior to the native
iOS Health Center. It does not include Android #4315's subsequent replacement of
import groups by sampling periods; that is a separate Android/iOS parity item.

## Implemented Activity Mapping

- Store encrypted daily step counts and cycling milliseconds in an indexed SQLite
  table with no rolling retention cutoff. Authenticate owner, sensor kind and
  local calendar date with each ciphertext. Replayed checkpoints can only raise
  a saved daily total, not decrease it.
- Import surviving motion checkpoints idempotently on load, before rolling
  updates discard earlier dates, and after accepting new motion evidence.
  Include confirmed active cycling intervals without mutating the live session.
  Do not invent older days that earlier versions did not retain. Unsampled step
  checkpoints do not create false zero readings.
- Add a separate Activity comparison route without changing the existing Today
  Steps/Cycling controls. Compare 7/30/90 days or 1-366 custom completed dates with
  the immediately preceding aligned period. Queries span at most 732 days.
- Show observed totals, observed-day averages, coverage, paired-only percentage
  changes, a current/previous bar chart and a full date-paired data disclosure.
  Missing dates remain `nil`, distinct from an observed zero. Calendar arithmetic
  rather than fixed 86400-second offsets preserves DST alignment.
- Bound background reads by the date index and discard stale or cancelled query
  results. Recheck local-summary consent on completion. Clear rendered health
  values on backgrounding, identity changes and protected-data loss.

## Verification Scope

Added XCTest source for monotonic/reopened history, owner/date authentication,
invalid and over-wide query bounds, migration before checkpoint replacement,
unknown-versus-zero dates, paired-only arithmetic and DST boundaries. Tests were
not executed, as requested. Additional XCTest source covers authenticated report
and table associations, selected report boundaries, exact secondary-link
revisions, pending original removal, unknown side compatibility, side/condition/
unit separation, source-pinned trend versions and report trend facts without
invented means or deltas. Updated the prior OCR trend expectation to require an
actual latest reading rather than a report average.

Project structure, whitespace, scoped localization-key and Swift grammar checks
are static checks only, not Xcode type checking or device verification. No
simulator screenshots or native interaction verification are claimed on Windows.

## Measurement And Trend Mapping

- Add a paged import/report selector, optional single-report scope, two-group
  comparison, out-of-range filter, original reference ranges and actual sampling
  timestamps. The overview can switch between latest measurements and a selected
  group without changing the live Steps/Cycling controls or capture actions.
- Derive capture/import identity from authenticated saved job/batch IDs, not the
  date of upload. Preserve report SHA-256 checks and exact current revisions for
  secondary links. Resolve table aliases against retained source bytes and their
  digest; undone imports and pending original removals cannot enter the view.
- Add backward-compatible optional measurement side metadata, explicit side
  selection in manual blood-pressure entry and normalized legacy unknown sides.
  Duplicate detection and comparable trend scope now keep side and collection
  conditions separate. Unknown side is never inferred to be left or right.
- Anchor comparable trends to the selected sampling date, initially spanning six
  calendar months. Pin unit, collection condition, side and source/device origin
  to that current reading. A changed anchor revision invalidates its cohort.
- Add latest-actual-reading aggregation. Do not average report/table results,
  draw continuous lines between unverified methods, or send invented numeric
  deltas/means in trend explanation facts. Actual values, source counts and point
  audit remain available. iOS has no verified laboratory-method field, so these
  report/table deltas remain unavailable rather than being guessed.
  Retain authenticated secondary-link provenance separately from a reading's
  primary source, so a previously manual reading linked to a report cannot bypass
  those unverified-method restrictions in comparison or trend explanations.
- Preserve source NavigationLinks while a child is pushed; clear sensitive
  projections through identity, foreground, consent and protected-data observers.

The iOS measurement projection uses the existing authenticated encrypted archive;
picker rendering is paged in groups of 30. This is not a claim that measurement
storage itself was migrated to Android's SQLite import-library schema. The new
permanent activity history, separately, uses indexed bounded SQLite queries.
