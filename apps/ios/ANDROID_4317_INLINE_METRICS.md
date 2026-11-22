# Android #4317: same-list measurement expansion and local filtering

Source: https://github.com/galaxyssi/GalaxySSI/pull/4317

Android merge inspected: `91dfdd85647e8452a8740854434d0aa4ca711093`.
This follows iOS #4421 / Android #4315. It intentionally supersedes that PR's
secondary historical-record expansion; it is not a second implementation of the
same Android change. It does not include Android #4316 / iOS #4422 changes.

## Mapping

- `GalaxySSIHealthMeasurementList` implements stable, current-result ordering:
  outside-range results, recorded normal results, then missing placeholders.
  Steps remain in the separate activity tile. All actual outliers are retained
  in the collapsed preview even when there are more than five.
- The abnormal filter uses only each displayed result's recorded/confirmed
  ranges. A normal latest result with earlier period outliers is not included;
  its historical outside-count caption remains in the unfiltered view.
- `GalaxySSIHealthMeasurementOverviewView` keeps one ForEach in one bordered
  metric container. Expanding appends the remaining metric rows with the same
  value/reference/caption/navigation renderer, not chronological historical rows.
  Existing preview identities are unchanged. The expansion control is shown
  only when rows are hidden. The unused secondary-list renderer is removed.
- Abnormal and expansion state are local to the measurement view. Neither
  changes its query scope, starts a worker or calls the parent's reload. They do
  not mutate the parent binding or reconstruct activity tiles/footer. The loaded
  summary supplies both filter states, including while background queries are
  unavailable. Toggling the filter does not reset expansion or scroll state.
- New measurements, source changes, consent, time-zone and sampling-period
  changes still reload/revalidate snapshots. Changing the selected sampling
  period resets expansion. Stored measurements/files/imports are unchanged.
- Hidden views stop starting queries from notifications. Pushing a detail keeps
  its source link alive; returning revalidates the snapshot. Backgrounding,
  identity changes and protected-data loss clear private query output. The
  SwiftUI view's event handlers/binding are released with the view lifecycle.

## Verification and limitations

Focused XCTest source covers actual-range filtering, prior-outlier exclusion,
empty/step-only data, more than five outliers, recorded-before-missing ordering,
stable expansion identities and repeated filter round trips. Source review
confirms filter/expansion actions contain no query/reload or parent mutation.

Static checks: `npm run check:ios`, modified/new Swift grammar parsing and
`git diff --check`. Tests are not executed, per request. No native compilation,
simulator/device UI tests, verified scroll screenshots or IPA on Windows. Stable
IDs and absence of scroll resets preserve the existing scroll container; actual
native layout/scroll restoration still needs device validation. iOS only.
