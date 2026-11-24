# Android #4493 iOS Port

Pinned Android open PR head: `d858b91af063b6a77960480d4acf1c1398f8a620`. This is not a merged Android commit; later Android amendments need separate review.
Incremental predecessor: iOS #4525, `28718cbf10eaf67b5b836944cc0d039ca5682bd6`.
The branch targets main but is cumulative, not an independent full-main diff.

## Changes

- Remove previous-period data from the activity model, history read window and plotted scale. Preserve nil gaps, recorded zero values, calendar-based day progression and monotonic archived/live overlays.
- Replace the all-values modal with a native interactive chart. Add date ticks, a current-only rounded Y scale, selected-point guide/ring and wrapping inline date/value tooltip. Single-day ranges are centered.
- Point taps select recorded data; blank/outside taps clear. Dragging and cancelled/multitouch input do not act as taps. Outside observation does not cancel List controls or scrolling. VoiceOver activation chooses the latest recorded point; adjustment and keyboard arrows move across recorded dates.
- Store kind, range and selected date in owner-scoped scene state, never storing measurement values there. Range/kind/timezone/identity changes clear selection. Background/protected-data transitions clear loaded measurements; existing consent, identity and request correlation checks remain.
- Import the exact point-value string pair from English and Chinese Android resources into a dedicated table. Do not bump iOS versions or change motion tracking/history retention.

## Evidence And Limits

Eight changed Android files are pinned and individually mapped in the source inventory and coverage manifest. Source/resource contracts check the new scope and preserve storage, motion and privacy kernels. Native model/accessibility fixture sources are updated but not executed.

Windows has no Xcode. No Swift type checking, XCTest run, VoiceOver/keyboard/tap/scroll gesture acceptance, native chart pixels/layout, scene recreation, real-device acceptance or IPA build is claimed. Android #4497 scrubbing is intentionally a separate port.
