# Android #4414 iOS Port

Pinned source: `7dd7f35525ed800b74a3439bf708b1793316de42`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4414

## Review Scope

Base is main. Inherits OPEN formal #4506, #4505, #4504, #4503, #4502, #4501,
#4500, #4499, #4498, #4496, #4495, #4494, #4492 and #4491. No predecessor
is assumed merged. The full main diff contains inherited work, not just this
feature. Incremental review base: `2d887e5a44afac865375463d454d02fcfb135100`
(#4506 head). Only iOS files change; no Android/Desktop edits or IPA.

All 119 original files have pinned hashes and explicit dispositions: 28 model
declarations, physiology routing, activity navigation, 58 resource XMLs,
29 unit-test references, one device-test reference and Android-only version.
See ANDROID_4414_SOURCE_INVENTORY.json and ANDROID_4414_PORT_COVERAGE.json.

## Implementation

- Add 28 native synthetic models with all 48 original controls and 30 new owners:
  accessory gland entry, AII amacrine relay, astrocyte recycling, cecal pouch
  mixing, clitoral route trace, club cell dome, dendritic outline, enteroendocrine
  polarity, intestinal stem renewal, Langerhans reach, macrophage clearance,
  mast granules, microglial surveillance, muscle satellite fusion, nail advance,
  pancreatic acinar apical band, Paneth release, penile path trace, plasma cell
  secretion, satellite glial sheath gap, scrotal heat tally, skull layers,
  splenic slit sorting, thyroid C-cell grid, follicular faces, urethral opening,
  vaginal ruga span and vestibular gland volume.
- Preserve ranges/defaults/scales/units/precision, axes/bounds, exact entry IDs,
  sources, primary formulas and companions. Whole diagram counts round at
  positive half steps; slit fits use exact thresholds, not rounded widths.
  Geometry and path samples stay continuous. Preserve signed relay branches,
  bounded counts, saturation, geometric arcs/areas and separate total pools.
  Companion values are not clamped to primary chart bounds.
- Preserve all original 67 literal routes and 216 preceding teaching owners.
  Source partition now covers 313 catalogue IDs / 123 model kinds with oxygen
  enabled, or 311 / 122 without it; this is not runtime coverage certification.
  Original artwork/function routes and assets are unchanged.
- Move the Numerical model navigation row immediately after functional playback,
  before related prose/lessons. Fallback artwork receives the same action.
  Snapshot the live function phase before switching; keep entry-local controls,
  artwork and other selections. Tab identity resets scroll to the top while
  persisted selections remain outside the scroll subtree.
- Import/register all 162 original English/Chinese resource delta pairs, including
  My metrics and Numerical model. Models remain synthetic and do not read,
  predict or transmit personal measurements.
- Update XCTest SOURCE fixtures for all 28 defaults, controls/owner totals,
  half-step counts, slit thresholds, signed branches, continuous geometry,
  descending chart axes and 30-owner phase/slider/tab/restoration contracts.
  These test sources were not executed.

## Source Verification And Limits

Passed 119 original file hashes/dispositions, Kotlin declaration reproduction,
resource extraction, native metadata/formula/delegation/navigation checks and
all preceding teaching source checks. Nine changed Swift files parsed without
grammar errors after conditional directives were removed. iOS project structure
and whitespace checks passed.

No Swift type checking/Xcode build, Android tests, XCTest execution,
device/simulator launch, pixel/gesture/VoiceOver acceptance or IPA. Android test
results are not iOS evidence. Inherited runtime/vector acceptance gaps remain;
source checks do not prove native UI parity or clinical accuracy. Formal PR
status is requested, not native certification.
