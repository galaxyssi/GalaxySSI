# Android #4389 iOS Port

Pinned source: `9508d49277cf33ab7f85e65722e7c470930fff7e`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4389

## Scope And Dependencies

This branch inherits formal iOS #4494, #4492 and #4491, not assumed merged.
The PR uses main, so its diff includes predecessors. Incremental review base:
`9f79db746d4c3d48f9820a23a8328a9bdcd49544` (#4494 head).
Only iOS changes; no APK/app version change or IPA generation.

All 72 original source files are pinned in ANDROID_4389_SOURCE_INVENTORY.json.
ANDROID_4389_PORT_COVERAGE.json explicitly maps 16 production files, 26 drawable
files, 20 bilingual XML resources, nine Android test references and one Android
packaging/version-only change. The pinned code changes APK version 0.18.163 to
0.18.164; the older version in the Android PR description is not used as source.

## Implementation

- Original Kotlin-evaluated declarations for 26 dedicated cutaways with 139
  local explanations and three canonical anatomy links.
- Imported all 408 vector paths with quadratic normalization, original fill rules
  and retained vector PDF metadata. No rendered screenshot parity is claimed.
- Imported all 331 exact English/Chinese resource pairs into the registered
  AtlasDetail table, with pinned native structure validation.
- Detail-first view routing preserves each original locator and stable selector
  identity, so users can return to the overview and restore either selection.
- Full screen anatomy has the body-exploration title, selected-name/caption,
  independent zoom/label state, localized hide/show controls, scale/offset reset
  and existing feature alerts/depth-limited canonical anatomy selection.
- Existing measured callout rails and dynamic type are retained. Controls remain
  outside labels; unlabeled mode removes rails/guides. UIKit scroll containers
  cancel UIButton touches when a label drag becomes a pan, retaining normal
  label clicks and native pinch handling.
- Historical default-view expectations were updated. Added XCTest source
  assertions for all 26 new defaults, local feature versus anatomy selection,
  distinct retained locators and independent restored view/zoom/layer state.
  These XCTest sources were not executed.

## Source Verification

- `check-atlas-detail-source-scope.cjs --checks` passed: all 72 source hashes/
  dispositions, original declaration re-extraction, data/graph/link identities,
  resource keys, runtime source wiring and exact resource re-extraction.
- PDF move/line/cubic/close operators match normalized source geometry across all
  26 resources; page sizes and vector resource metadata checked.
- Five changed Swift files parsed with zero grammar errors after conditional
  directives were removed. This does not type-check Swift.
- `npm run check:ios` project metadata and `git diff --check` passed.

## Outstanding Native Acceptance

No Swift/Xcode build, XCTest, simulator/device launch, touch/rotation/large-text
exercise, VoiceOver, screenshot/alpha/pixel check or native restoration acceptance
was performed. Source checks do not substitute for these. The PR is formal,
non-draft at the user's request, not a claim of native certification. Inherited
historical vector/native acceptance gaps remain documented in predecessor ports.
