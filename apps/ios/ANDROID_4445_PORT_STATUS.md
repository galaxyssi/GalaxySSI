# Android #4445: integrated figure explanations

## Source and dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4445
- Merge: `9ec28d754459358556c570134171c79b55951982`.
- Incremental iOS base: `cdf7c9587c94c4be40f416047fbe675499e479f5`, PR #4521.
- 27 original paths without rename folding: 11 production Kotlin paths, 11 Android device/helper references, four XML resources and one version-only file. Inventory hashes deleted SceneFrame content from the parent revision, not the revision in which it no longer exists.

## Native implementation

- Shared figure frame with optional header, full-width artwork and legend, bounded 28-point overlap, 18-point transparent-to-ground fade, horizontal 16/top 18/bottom 14 legend insets, exact day/night ground colors and rounded clipping. The active function scene no longer uses the previous dark caption band; its old palette fixtures remain historical.
- Chapter and caption reserve their longest wrapped content with the same native Text/font/width through the existing hidden caption probes. Chapter tint returns to the health accent, prose to adaptive primary. Existing playback clocks, viewport policy and rendering kernels remain unchanged.
- Structure becomes figure-only. Remove the old organ/tissue/cell detail tabs, below-art relationship lists and duplicate description/source/art-note rows. Preserve the catalogue graph, tissue/cell searches, view variants and image label destinations.
- Move layers/reset/fullscreen/source icon controls above the image. Layers contains only actual marker destinations plus plate features (whole-body systems are retained), excluding self. Hide the menu without choices. Preserve pinch zoom, label toggle, native tap-versus-drag cancellation and feature dialogs.
- Whole/entry artwork minima are 366/266 points; callout rails reserve bottom 28 in normal and fullscreen figures, with default-zero arguments preserving other users. In-figure title/description/note use scalable 14/15/12-point text. Entries without artwork use a native concept symbol plus an exact translated non-anatomical disclaimer, never an unrelated anatomical plate.
- Fullscreen uses the same figure legend and entry/plate caption; explanation is not duplicated. Zoom/reset/label and feature behavior remains native.
- Simulation wraps circulation/gas/generic process artwork with the same reserved stage legend. Bottom padding outside the unchanged drawing and stage-hit kernels keeps the overlap off the interactive process region. Retina/endocrine retain their own stage presentation. Germline stage description moves to the process legend. Numerical invocation/placement, timers, pause/reset and reference disclosures remain exact.
- Search is available from detail, research and standalone model surfaces. Start with organs, cleared query/system/tissue mode, 24 results and native focus; retain tissue/cell/system navigation and 100-character query bounds. Pause and snapshot the originating selection, view variant, precise function phase and scroll before presentation. Cancel restores it; choosing a result goes directly to Structure with no intermediate catalogue history. Back restores the origin while retaining independent destination-course progress and numerical settings.
- Search and direct-result navigation are included in the bounded public navigation archive, reuse existing selection sanitizers and reject unknown/mismatched/depth-exhausted contexts. Surface-specific links prevent inactive parent, research or standalone containers from claiming each other's search/result navigation.
- One exact English/Chinese concept-symbol disclaimer pair. No iOS version bump, model payload or IPA.

## Verification limits

Source/resource/project/grammar/whitespace checks only. Added Swift fixture sources cover search cancel, same-entry direct result/Back, source view/phase/scroll preservation, archive restoration, surface isolation, malformed search archives, depth exhaustion and bounded figure/callout inset math. They have NOT been executed.

Windows has no Xcode. No Swift type checking, XCTest, simulator/device, native focus/keyboard, modal/back gestures, font layout, scroll pixels, moving-image sweep, recreation timing, screenshots or IPA validation is claimed. Original Android device results are source references, not iOS evidence.

Historical source audits explicitly accept this newer figure/search layout while retaining exact playback/lifecycle, numerical, chapter/evidence-menu, immutable resource and personal-metric contracts. The prior dark caption colors are not presented as the current active UI.

## Review scope

Formal PR base is `main`, but the branch cumulatively includes preceding unmerged iOS work through #4521. It is NOT an independent #4445 main diff. Review the incremental port against the exact base above; integrate predecessors in order or deliberately reconstruct integration. The entire Android backlog remains in progress.
