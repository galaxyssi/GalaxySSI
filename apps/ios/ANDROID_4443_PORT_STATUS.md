# Android #4443: film captions and rod phototransduction

## Exact source and scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4443
- Merge: `c63bffe14e00a4c60e52aec68b6753f7547be308`.
- Incremental iOS base: `2f5427312748cdf8188ad13c1d462106ce98a4da`, PR #4519.
- Eleven original files: four production Kotlin, two test references, two theme XML, two string XML, one Android version-only change. Each source hash and disposition is in the inventory/coverage JSON.

## Native implementation

- Full-width art and a contiguous zero-gap caption band. Copy exact day/night ground and band colors, inherited mint chapter and white prose, 14-point horizontal caption padding and 12-point bottom padding. Diagram rendering kernels keep their original appearance.
- Reserve complete wrapped text with the same native SwiftUI Text type and modifiers used for display, including inherited font, fallback glyphs, Dynamic Type and current proposed width. Explicit unlimited lines on both probes and visible text. Hidden probes do not participate in accessibility. Android's platform-specific probe-TextView fix is a native-renderer parity requirement, not a reason to add Android APIs or a second iOS font estimator.
- Magnified rod outer-segment membrane during the VISION capture chapter: light arrives first, cGMP declines, cation channels close, membrane becomes more negative and transmitter release decreases. Preserve original normalized transition timing, pigment/messenger indicators, gate gap, ion and transmitter counts. These are qualitative teaching values, not patient measurements.
- Preserve optics, retinal relay, axon and adaptation scenes and original trajectory kernels. One new original experiment reference is appended only to VISION through a pinned idempotent overlay; 138 stories, 643 chapters, 313 routes and phases remain, with 324 references.
- Eight translated English/Chinese pairs plus two explicitly non-translatable scientific names, ten entries per locale table. Source XML attributes determine shared names; no invented translation or implicit fallback. No iOS version bump.

## Verification and limitations

Source/resource contracts, project registration, grammar parsing and whitespace checks only. Compare the six original theme values, compute source-color contrast, verify the rod sequence formulas, keep numerical/playback/lifecycle and other drawings frozen. Swift fixture sources cover response ordering/monotonicity/clamping, exact palettes and complete reference-overlay field preservation; NOT executed.

Windows has no Xcode: no Swift type checking, XCTest, device/simulator, actual narrow-width/mixed-script/large-type measurement, pixel containment/height/contrast, moving-region hash, screenshot or IPA. Computed color contrast is not rendered-pixel evidence.

The original Android PR body records unresolved playback-clock and multi-entry closeup device failures despite other passing checks. This port does not claim to fix those failures, reproduce Android device results, or certify iOS playback/native acceptance. iOS clock/control/numerical code remains unchanged. Follow-up device verification is still needed on an Apple platform.

## Review dependency

Formal PR base is `main`; earlier unmerged iOS work through #4519 is cumulatively included. This is NOT an independent #4443 main diff. Review this port with the exact incremental base above, then integrate predecessors in order or reconstruct integration deliberately. No completion claim for the full Android backlog.
