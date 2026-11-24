# Android #4497 iOS Port

Pinned OPEN Android head: `6071f168d789cc0657306042b9735a512bd04e64`, incremental Android base `d858b91af063b6a77960480d4acf1c1398f8a620` (#4493). Neither is claimed merged.
Incremental iOS predecessor: #4526, `a95357af78c71b82a60f2460e4601e3b95956313`. Main-targeted branch is cumulative, not an independent full-main diff.

## Changes

- Tap the timeline by horizontal date position rather than hitting a dot. Clamp/round to the nearest calendar date, including missing dates and single-day ranges.
- A directional UIKit recognizer continuously selects during horizontal scrubs; vertical movement fails early for the ancestor scroll view. Multitouch and cancellation terminate tracking; blank/outside taps clear selection without consuming List controls.
- Missing dates show the localized no-record readout with a guide and mid-height tooltip, never a fabricated zero-value dot. VoiceOver and keyboard navigation now visit every calendar date.
- Freeze live display updates while a touch is tracked. On completion/cancellation, asynchronously apply the latest local motion state. History storage/retention, motion tracking, selected-range reads and consent/identity/protected-data/request checks remain unchanged.
- Import the exact English/Chinese no-record pair in its own resource table; preserve the #4493 table. The prior checker explicitly delegates superseded point-only contracts to the follow-up checker while retaining its pinned source inventory.

## Evidence And Limits

Eight incremental Android changed files are pinned and individually mapped. Source/resource checks freeze unchanged model, storage, query and drawing kernels. Native fraction/accessibility fixture sources are updated but not executed.

No Swift type checking, XCTest, actual gesture/scroll arbitration, deferred-update timing, native layout/pixels, VoiceOver/keyboard, scene recreation, physical-device acceptance or IPA build is claimed. Windows has no Xcode.
