# Android #4407 iOS Port

Pinned source: `2b0a455e59948d31606010edf3ddba25d01c180f`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4407

## Review Scope

Base remains main. This branch inherits OPEN formal #4503, #4502, #4501, #4500,
#4499, #4498, #4496, #4495, #4494, #4492 and #4491; none is assumed merged.
The full main diff includes predecessor work, not just this feature.
Incremental review base: `d4ab3b41ef96a2915eb62e249775e0c2bbe41814` (#4503 head).
Only iOS files change; no Android/Desktop change, version bump or IPA.

All 45 original changed files have pinned hashes and explicit dispositions:
14 production files, 18 resource XMLs, ten unit-test references, two device-test
references and one Android-only APK version file. See the source inventory and
ANDROID_4407_PORT_COVERAGE.json. Android test results are not iOS evidence.

## Implementation

- Nine native teaching models: vocal cycles, vertebral series, oral marker
  dilution, olfactory surface retention, circadian light window, adipose volume
  share, thymic branching, gastric precursor balance and melanin distribution.
  Preserve all 18 controls, 19 exact owners, scales/units/digits, axes/bounds,
  assumptions and sources. Existing literal routes and prior owners are intact.
- Preserve cumulative circadian degrees versus wrapped dial position, cubed
  radius cell/tissue volume shares, synthetic tile/precursor/marker budgets and
  model-time cycle counts. None reads personal measurements or records audio.
- Native paired vocal-fold cutaway and 145-point ideal opening curve use one
  cosine opening function and shared phase. Preserve original cubic folds,
  square-root gap, chart/cursor, geometry/colors and fitted localized labels.
  This is a relative opening curve, not an audio signal or clinical voice model.
- Add optional 1000-step scrubbing to the shared native player. Seek pauses,
  clamps finite positions and updates drawing/curve together without changing
  selected frequency/time. Resume, replay, model/reset final target, Reduce
  Motion handling and lifecycle pause remain shared. Vocal playback is 2.4
  seconds; bladder/ureter retain previous defaults and have no scrub slider.
- Native circadian light/dark dial retains twelve ticks and wrapped-phase hand;
  adipose cell droplet and tissue sector retain separate radius/volume budgets,
  original coordinates/colors, labels and accessible descriptions.
- Import/register all 67 exact English/Chinese pairs as AtlasPhaseTeaching and
  include the new Swift view in Xcode. Existing localized cycles display is
  reused; synthetic units match original source.
- XCTest SOURCE contracts cover new defaults/all slider pairs, conservation,
  phase wrap boundaries, fractional input, ideal opening extrema/finite bounds,
  seek/pause/resume/reset, unchanged selected inputs and 19-owner restoration
  without altering artwork/function selection. Conditional coverage assertions
  are now 77 models/240 entries with oxygen or 76/238 without. XCTest was NOT run.

## Source Verification And Limits

Passed source inventory/dispositions, original declaration/resource reproduction,
exact metadata/formula/owner/routing checks, playback wiring checks and preceding
teaching source checks. Twelve changed/added Swift files parsed without grammar
errors after conditional directives were removed. Project structure and
whitespace checks passed.

No Swift type checking/Xcode build, Android tests, XCTest, simulator/device launch,
native playback/numerical/gesture/pixel/VoiceOver acceptance or IPA. Source
checks do not establish runtime model coverage or screen parity. Inherited
runtime/vector gaps remain documented. Formal PR status follows the user's
request, not native certification.
