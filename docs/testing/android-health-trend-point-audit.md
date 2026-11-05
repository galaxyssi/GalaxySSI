# Android health trend point audit

A single-record chart point continues to open its exact record revision.
A multi-record mean, minimum or maximum opens a point-specific audit with
the series, aggregation, value, unit, date window, source and contributor
count. An extremum exposes its exact winning revision even when that row
is on a later page.

Only the selected series and scope metadata travel between activities.
The audit recomputes the selected bucket from its authenticated records,
using the chart's aggregation implementation and the entire original
bucket as one interval. It pins the same measurement version, excludes
records outside that scope, and clears the visible audit if the metric
changes. Values and source names are dropped on stop, not put into
saved state. Returning preserves the contributor page and scroll position;
the chart only restores its selected point if the scope and version agree.

The test fixtures include a multi-day point, a two-page minimum with mixed
sources and units, the exact extremum revision, navigation back to the
selected point, and an edit while the audit is visible.

All 73 trend, catalog, weekly-report, and assistant device tests passed
without skips on a physical Samsung Tab Active3 (SM-T575) with 0.1.7.67.
