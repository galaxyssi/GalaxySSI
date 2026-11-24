# Android #4401 iOS Port

Pinned Android source: `e228e379f307fcd6c1eb93b289126e9c473ddf7e`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4401

## Review Scope

Base remains main as requested. This branch inherits OPEN formal #4500, #4499,
#4498, #4496, #4495, #4494, #4492 and #4491; none is assumed merged. The actual
main diff includes their changes and is not an independent organ-model-only diff.
Incremental review base: `e9f997a5779c95cc9db53e0a826fc757e1c63388` (#4500 head).
Only iOS files change; no Android/Desktop change, version bump or IPA.

All 45 original files have pinned hashes and explicit dispositions:
12 production files, 18 bilingual resource XMLs, ten unit-test references,
four device-test references and one Android-only version file. See
ANDROID_4401_SOURCE_INVENTORY.json and ANDROID_4401_PORT_COVERAGE.json.

## Implementation

- Nine explicit native models: arterial continuity, glial capacitance, colonic
  water balance, lymph particle transport, endocrine dilution, bone section,
  retinal convergence, muscle shortening and keratin growth. All 18 control
  ranges/defaults/scales/units/digits, axes/bounds, source URLs, disclaimers and
  42 owner IDs follow the original specifications.
- Preserve original 67 literal routes and all 69 preceding teaching bindings.
  New owners are disjoint; existing anatomy/function assets and 313 playback
  bindings are not edited. Native source expects conditional 50-model/178-entry
  coverage with oxygen or 49/176 without oxygen, not certified runtime coverage.
- Retain bounded/finite input guards, synthetic-only public context, entry-local
  restoration, sliders, result/companion, curve, reset and source links. Preserve
  stable log1p cylindrical capacitance, hollow-shaft cortical area, fixed five-
  minute transport collection, fractional expected retinal counts and metric
  serial-sarcomere shortening with three-digit result formatting.
- Original reactive arterial lumen/wall/diameter ticks, normalized speed ruler,
  positive-flow arrow and zero-flow dot are drawn in 340x156 coordinates. Exact
  original dimensions/colors, localized legends and accessibility descriptions
  are retained; no pixel or gesture parity is certified.
- Import/register 57 exact English/Chinese resource pairs in AtlasOrganTeaching.
  Existing localized display-unit logic is unchanged.
- Added XCTest SOURCE contracts for all new defaults and slider combinations,
  conservation/dimensions, fractional retinal expectations, nondefault muscle
  shortening, invalid inputs, 42-owner state isolation and unchanged artwork/
  function selection. Update old triceps/lymph owner and decreasing-axis
  expectations. Existing iOS curve identifiers already match Android test fixes.
  XCTest and Android tests were NOT executed.

## Verification Limits

Source checks reproduce declarations/resources and verify file hashes, explicit
formulas, metadata, owner bindings and prior route preservation for #4397,
#4399 and #4401. Grammar parsing is not Swift type checking or execution;
project metadata checks do not build an iOS app.

No Swift/Xcode build, XCTest, simulator/device launch, native numerical/UI/
VoiceOver/pixel acceptance or IPA. Inherited runtime/vector acceptance gaps
remain documented. Formal PR status follows the user's request, not device
certification; source assertions do not establish running 50-model coverage.
