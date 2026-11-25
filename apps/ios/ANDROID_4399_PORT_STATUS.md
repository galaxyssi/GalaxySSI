# Android #4399 iOS Port

Pinned source: `de05fd51ba151789acd24dc4484d7f84d893aea3`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4399

## Review Scope

This branch inherits open formal PR #4499 and its predecessors #4498, #4496,
#4495, #4494, #4492 and #4491; none is assumed merged. Base remains main, so the
actual PR diff includes those changes. Incremental review base is
`95234c4312487ef9d6ea38ce2f3fa90e13703959` (#4499 head).
Only iOS files change. No Android/Desktop modifications, version bump or IPA.

All 48 source files have pinned hashes and explicit dispositions in
ANDROID_4399_SOURCE_INVENTORY.json and ANDROID_4399_PORT_COVERAGE.json:
14 production files, 20 resource XMLs, 12 unit-test references, one device-test
reference and one Android-only APK version file.

## Implementation

- Nine new native teaching kinds: diaphragm displacement, cardiac phase time,
  visual angle, serial absorption, hormone signal, immune composition, duct
  transit, oviduct ciliary cycles and knee moment. All 18 controls and 35 owner
  bindings match original ranges/defaults/scales/precision/units/axes/bounds.
- Existing 67 literal route clauses and preceding 34 teaching owners retain
  precedence. New owners are disjoint. Model results, companions, source links,
  localized disclaimers/context, sliders, chart and reset use existing native
  infrastructure and independent per-entry restoration. No patient estimate or
  health-record access is introduced.
- Reactive diaphragm drawing preserves original 340x156 coordinates, square-root
  area scaling, chest and dome cubic paths, displaced-area fill, resting dashed
  and current solid lines, conditional arrow, accessible description and legends.
- All 60 English/Chinese resource pairs are imported from structured source XML
  and registered in Xcode as AtlasSystemTeaching. Localized bpm/cells/cycles are
  used in input/output, axis/plot units and slider accessibility values. Other
  units, including synthetic DU/min and LU/TU, remain unchanged.
- Native XCTest source includes nine new default fixtures, all new slider pairs,
  conservation identities, partial cycles, unit conversions, invalid input,
  localization and isolation/restoration of all 35 new owners. Old heart/atrium
  and decreasing-curve expectations are updated. Conditional coverage assertions
  now expect 41 models/136 entries with oxygen, or 40/134 without it.
  XCTest was not executed.

## Verification Limits

Source checks compare pinned original declarations and file hashes, preserve
prior routes and specifications, and reproduce bilingual resources. Grammar
parsing does not type-check or execute Swift. Project metadata checks do not
compile an iOS app.

No Swift/Xcode build, XCTest, simulator/device launch, native numerical/UI/pixel
acceptance or IPA was performed. Inherited runtime/vector acceptance gaps are
not resolved by this port. Formal PR status follows the user's request, not
native certification. Source checks cannot establish running 41-model/136-entry
coverage or screen parity.
