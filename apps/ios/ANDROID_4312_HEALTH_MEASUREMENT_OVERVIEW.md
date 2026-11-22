# Android #4312: compact Health Center measurement overview

Source: https://github.com/galaxyssi/GalaxySSI/pull/4312
Android merge: `9568d1c18247e0c51e1beed8e8c4f5bbd7e2f785`

## iOS mapping

- Replace the first-use introduction and expanded inline measurement rows with
  a local-date heading, paired step/cycling tiles and compact measurement rows.
  Tiles stack below 312 points of content width (344 including page insets) and
  at large Dynamic Type settings. Existing Motion authorization and goal editing
  are reused; no location collection is added.
- The four persistent capture/connection actions remain available on empty and
  populated overviews. Photo capture, report recognition and multi-file import
  are unchanged. Existing configuration destinations remain in More.
- Each non-step measurement opens a separate detail view containing provenance,
  context, comparison ranges, source references, three recent readings and its
  complete history. Out-of-range measurements retain the comparison note.
- A private-discussion entry is shown only for the exact current measurement
  revision and a current, active local-care concern with summary/profile consent.
  Recheck eligibility on tap and retain the existing discussion data-preview and
  explicit send authorization; opening a detail does not send health data.
- All records and metric history group the existing bounded visible pages by
  local calendar day, keeping source/time and numeric or reported-result values.
  Refresh grouping on time-zone changes. Identity, protected-data and foreground
  boundaries clear sensitive detail and history projections.
- Cycling totals of at least one hour display hours/minutes; shorter totals keep
  minute and under-one-minute labels. English fallbacks and Chinese resources
  are included. Android/Desktop version numbers are not modified.

## Verification scope

Added XCTest source for local-day/DST grouping and visible-page boundaries,
recent reading eligibility, current-revision/consent discussion gating and
cycling duration formatting. These tests were not executed, as requested.
Targeted project structure, whitespace, localization-key and Swift grammar
checks are static checks only. Xcode type checking, native screenshots,
simulator interaction and physical-device behavior are not verified on Windows.
