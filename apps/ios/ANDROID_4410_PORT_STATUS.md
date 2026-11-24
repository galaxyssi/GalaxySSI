# Android #4410 iOS Port

Pinned source: `e8ddebdcc70942880fcfeaacee57474c2d711b32`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4410

## Review Scope

Base is main. Inherits OPEN formal #4504, #4503, #4502, #4501, #4500, #4499,
#4498, #4496, #4495, #4494, #4492 and #4491; none is assumed merged. The full
main diff includes predecessor work, not just this feature. Incremental review
base: `5b6e5bfadd94159e0a5eaa671f0ec09882b33139` (#4504 head).
Only iOS files change; no Android/Desktop change, version bump or IPA.

All 44 original changed files have pinned hashes and explicit dispositions:
13 production files, 18 resource XMLs, ten unit-test references, two device-test
references and one Android-only APK version file. See the source inventory and
ANDROID_4410_PORT_COVERAGE.json. Android test results are not native iOS evidence.

## Implementation

- Nine native models: placental marker, renal tubule retention, Merkel contact,
  tooth enamel section, mucosal sampling, mammary duct delivery, rectal reservoir,
  stromal matrix and mucus film thickness. Preserve all 18 controls, 22 owners,
  ranges/defaults/scales/units/digits, axes/bounds, source URLs and assumptions.
  Existing literal routes and all previous teaching owners are intact.
- Preserve half-equilibrium transfer, sequential tubule reclamation, surface
  average mN/mm2-to-kPa pressure with a derived 80/pi chart ceiling, enamel ring
  share versus inner area, marker/volume conservation and synthetic patch/film
  dimensions. Models do not read personal measurements or make patient estimates.
- Shared validated tubule amounts drive both numerical outputs and the three-node
  diagram; starting/after-A/after-B amounts and separately reclaimed quantities
  retain their original meanings, including fractional curve samples.
- Native placental playback runs for 2.3 seconds, disables at zero transfer and
  preserves separate maternal/fetal lanes. Thirteen barrier cells, two eight-slot
  marker budgets, square-root filled marker areas, moving marker and fitted
  labels retain source geometry/colors. Presented amounts conserve the selected
  total without modifying inputs or depicting mixing of the blood lanes.
- Retain shared pause/resume/replay, model/reset final target, entry identity,
  lifecycle pause and Reduce Motion handling; no scrub slider is added here.
- Native enamel rim/interior/thickness marks and serial tubule arrows/nodes
  preserve original coordinates/colors/labels and accessible descriptions.
- Import/register all 70 exact English/Chinese pairs as AtlasExchangeTeaching,
  plus the native amount helpers and placental view in Xcode. All original
  artwork and 313 function playback bindings remain unedited.
- Added XCTest SOURCE contracts for defaults/all slider pairs, conservation and
  surface dimensions, fractional values, amount guards, phase frames and 22-owner
  independent restoration. Placenta settings at 25 and trophoblast defaults at
  50 are separately preserved across restoration/reset. Conditional mapped
  assertions now expect 86 models/262 entries with oxygen or 85/260 without.
  Neither XCTest nor Android tests were run.

## Source Verification And Limits

Passed source inventory/dispositions, original declaration/resource reproduction,
exact metadata/formula/owner/routing checks, diagram/playback wiring and preceding
teaching source checks. Twelve changed/added Swift files parsed without grammar
errors after conditional directives were removed. Project structure and
whitespace checks passed.

No Swift type checking/Xcode build, XCTest, Android tests, device/simulator launch,
native numerical/playback/gesture/pixel/VoiceOver acceptance or IPA. Source
checks cannot certify runtime model coverage or screen parity. Inherited runtime/
vector gaps remain documented. Formal PR status follows the user's request,
not native certification.
