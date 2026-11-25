# Android #4412 iOS Port

Pinned source: `c704a171da9336535ab659d65e6c6af0a4ebd9ba`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4412

## Review Scope

Base remains main. Inherits OPEN formal #4505, #4504, #4503, #4502, #4501,
#4500, #4499, #4498, #4496, #4495, #4494, #4492 and #4491; none is assumed
merged. The full main diff includes predecessor work, not just this feature.
Incremental review base: `ae2a04394ad40224fafea1e4173b306869fa0dc8` (#4505 head).
Only iOS files change; no Android/Desktop change, version bump or IPA.

All 44 original files have pinned hashes and explicit dispositions: 13 production
files, 18 resource XMLs, 11 unit-test references, one device-test reference and
one Android-only version file. See the source inventory and
ANDROID_4412_PORT_COVERAGE.json. Android verification is not native iOS evidence.

## Implementation

- Nine native models: pleural slide, retinal light attenuation, gamete path
  distance, testis tubule section, uterine lining area, vulvar fold overlap,
  capillary support surface, marrow renewal and ependymal beat phase. Preserve
  all 18 controls, 21 distinct owners, ranges/defaults/scales/units/digits,
  axes/bounds, source URLs and synthetic-only assumptions.
- Preserve shear/stress, exponential attenuation, separated synthetic positions,
  ring and cylinder geometry, bounded projected overlap, signed whole-icon net
  renewal and unwrapped versus wrapped phase. Rounded whole inputs remain
  distinct from fractional geometry and curve samples; derived capillary bounds
  retain the source circumference-times-length calculation.
- Native 2.3-second pleural playback disables at zero speed. Five tissue/film
  bands, original gap scaling, clipped wall features, four tracer rows with
  linearly varying relative speeds, bracket and labels retain original geometry
  and colors. Shared pause/resume/replay/reset, lifecycle/Reduce Motion behavior
  and entry identity remain independent from selected model inputs.
- Native retinal layer preserves thickness, coefficient-dependent tint alpha,
  incident/internal/transmitted rays, intensity-dependent alpha/width, marker
  and original legends. Existing UInt32 ARGB decoding retains transparency.
- Import/register all 64 exact English/Chinese pairs as AtlasPleuralTeaching and
  include the new Swift view in Xcode. Existing localized cycles display is
  reused; synthetic units match source.
- Existing model routes, all 313 original artwork/function playback bindings and
  the inherited digestive cross-section selector fix are unchanged.
- Added XCTest SOURCE contracts for defaults/all new slider pairs, geometry/
  conservation, half-step renewal, signed totals, phase wrap, finite tracer
  helpers and pause/settings isolation. Add 21-owner restoration expectations
  without altering artwork/function selections. Conditional mapped assertions
  now expect 95 models/283 entries with oxygen or 94/281 without. Tests were
  NOT executed; assertions do not establish running coverage.

## Source Verification And Limits

Passed source hashes/dispositions, declaration/resource reproduction, metadata,
explicit formula/owner/routing checks, diagram/playback/alpha wiring and previous
teaching source checks. Eleven changed/added Swift files parsed without grammar
errors after conditional directives were removed. Project structure and
whitespace checks passed.

No Swift type checking/Xcode build, Android tests, XCTest, device/simulator launch,
native numerical/playback/zoom/gesture/pixel/VoiceOver acceptance or IPA. Source
checks do not prove runtime coverage or screen parity. Inherited runtime/vector
gaps remain documented. Formal PR status is requested, not native certification.
