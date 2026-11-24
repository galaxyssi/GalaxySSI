# Android #4402 iOS Port

Pinned source: `0d0112b055947c3747c7910b255aa299587dfd75`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4402

## Review Scope

Base remains main. Inherits OPEN formal #4501, #4500, #4499, #4498, #4496,
#4495, #4494, #4492 and #4491; none is assumed merged. The full main diff includes
predecessor changes, not just this feature. Incremental review base is
`c27acd35adef99372006a6371345aace2e0f6cb5` (#4501 head).
Only iOS files change. No Android/Desktop change, version bump or IPA.

All 43 original changed files have pinned hashes and explicit dispositions:
13 production files, 18 bilingual resource XMLs, ten unit-test references,
one device-test reference and one APK version file. See the source inventory
and ANDROID_4402_PORT_COVERAGE.json.

## Implementation

- Nine native models: bladder expansion, vestibular tilt, airway ciliary
  clearance, gastric liquid emptying, bile storage, thoracic cross-section,
  platelet fragment count, bone remodeling balance and cutaneous sebum.
  Preserve all 18 controls, 19 exact owners, ranges/defaults/scales/units/digits,
  axes/bounds, source URLs and synthetic-only scopes. Earlier routes retain
  precedence; new owners are disjoint.
- Preserve spherical volume/area scaling, atan2/hypot vestibular cues, fractional
  ciliary/gastric curve samples, synthetic marker conservation, elliptical
  cross-section, whole-positive-count half-up rounding and signed bone balance.
  Generic native sliders, response curves, reset, source links, context and
  independent per-entry restoration remain connected.
- Native bladder diagram plays linearly over 1.8 seconds, pauses/resumes/replays,
  disables at zero added volume and resets to the selected final volume on model
  change or explicit reset. Playback never mutates selected numerical inputs.
  Entry identity isolates playback; background/disappear/reduce-motion handling
  pauses it. Original cubic chambers, sphere-radius scaling, two-stop gradient,
  wall/lining strokes, arrow and localized volume labels are retained.
- Native ciliary transport diagram preserves nine lining cells, four quadratic
  cilia per cell, mucus track, marker, conditional arrow, original coordinates/
  colors and localized legends/accessible description.
- Import/register all 62 exact English/Chinese pairs as AtlasRegionalTeaching;
  new Swift view and table are included in Xcode. Existing localized cycle-unit
  display applies to ciliary input.
- XCTest SOURCE contracts cover nine defaults, all new slider pairs, volume/
  area/conservation, half-step platelet counts, fractional gastric/ciliary
  outputs, signed bone changes, invalid inputs and 19-owner state isolation.
  Conditional mapped-entry assertions are 197 with oxygen or 195 without it
  (59 or 58 model kinds). They are not native runtime acceptance evidence.

## Verification Limits

Source checks reproduce pinned declarations/resources and compare metadata,
formulas, owners, lifecycle wiring and prior routes for #4397/#4399/#4401/#4402.
Swift grammar parsing is not Swift type checking or numerical execution.
Project structure checking is not an Xcode build.

No Android tests, XCTest, Swift/Xcode build, device/simulator launch, native
playback/numerical/gesture/pixel/VoiceOver acceptance or IPA. Inherited runtime/
vector gaps remain documented. Formal PR status follows the user's request,
not native certification. Source assertions do not prove running screen parity.
