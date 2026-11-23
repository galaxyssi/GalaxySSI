# iOS parity: Android #4341 ear anatomy and hearing

Base: main. Android source: #4341, merge 29ca9c01d6e1ef8a156b77650448168a0ed09298.

## Scope

- Import the six exact Android ear entries and four-stage organ mechanisms as
  an additive bundled pack; preserve all existing microscopic processes.
- Convert 17 original ear-section paths to a transparent vector-preserving PDF,
  retaining five localized anatomy hotspots, shared captions, layers and fullscreen.
- Add bounded effective eardrum area, stapes footplate area and lever controls
  to ear/middle-ear only, with pressure ratio, separate dB gain, inverse
  volume-velocity ratio, shared-scale discs and the response curve.
- Preserve per-entry settings and current teaching context in physiology previews.
  Do not apply this model to cochlear/vestibular pathways or personal observations.
- Import 42 English/Chinese strings per language and the Android light/dark
  diagram colors. Allow only the exact NIDCD anatomy reference.
- No microphone access or test tones are introduced.

## Verification

- iOS project structure and changed-source Swift grammar checks passed.
- All 84 hearing localization entries match Android XML.
- Ear resource entries/mechanisms match the Android source delta.
- The PDF asset was rendered using Poppler and visually inspected. This is
  asset verification, not a native iOS UI screenshot or device acceptance.
- Added XCTest source for numeric fixtures, conservation, bounds, per-entry
  restoration, six mechanism owners, five hotspots and preview isolation.
  XCTest was not executed.
- No Xcode compilation, simulator/device execution or IPA is claimed on Windows.

This is a formal, main-based iOS-only PR. Earlier eye and aging feature code is
not duplicated in the change set.
