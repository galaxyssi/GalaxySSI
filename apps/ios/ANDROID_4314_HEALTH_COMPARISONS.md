# Android #4314: Health activity and measurement comparisons

Source: https://github.com/galaxyssi/GalaxySSI/pull/4314
Android merge: `e2bf99432f61f6658e98f545d6072ac8a7b9ccc8`

## Development Status

This branch is still in development and is not a submitted or completed parity
PR. Activity history and comparison are implemented below; report/measurement
selection and source-aware trend changes still require integration before the
corresponding formal PR is created.

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
not executed, as requested. Project structure, whitespace and Swift grammar
checks are static checks only, not Xcode type checking or device verification.

## Remaining Android Scope

- Select report/import groups and authenticated primary/secondary report links;
  compare actual measurements without confusing upload and sampling timestamps.
- Preserve units, collection conditions and source/device identity in comparable
  trend routes; retain actual report results rather than fabricating averages or
  connecting unverified laboratory methods.
- Review Android #4315's subsequent replacement of upload batches by clinical
  sampling periods separately. This document does not claim those later changes
  are implemented by the activity-history work above.
