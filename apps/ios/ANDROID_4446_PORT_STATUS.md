# Android #4446: connected in-image annotations

## Source and dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4446
- Merge: `cb3e3ca49c2d8aade7b190f1c82400d40a462806`.
- Incremental iOS base: `916e8a5bc3c79f0d612c829b413cc913cceab352`, PR #4522.
- 17 original files: 12 production Kotlin, four Android device references, one version-only file. Inventory and per-file coverage retain each original hash and disposition.

## Native implementation

- Replace the former 28-point fading footer with a connected annotation note. Use 12-point outer edges, 16-point gutter, 12/8/9 note insets, an adaptive surface and accent border, elbow leader and three-point endpoint dot. Notes precede the art in portrait, sit to its left in side layout, and render above overlapping art.
- Side notes at width >=580, or >=280 for independent/unlabelled/concept illustrations. Side width is 40% capped at 328; portrait uses 72% for animation overlays or 83% otherwise. Short constrained fullscreen windows switch to 44% side notes when the remaining drawing height would be under 160. Overlay is limited to half the measured note height and 46 points, and disabled for side/reserved notes.
- Native Text probes and visible captions share the same font, width, truncation and optional line cap. Function summary becomes 13-point/two-line, without the former separate title. Tapping it pauses through the existing player pause/commit callback and presents the complete caption with a frozen current chapter/title. Closing does not resume, seek or reset the player.
- Structure and fullscreen notes connect to the real image focus. Use a current-entry marker, the pinned beta-cell focus, or the original layout-dependent default. UIKit conversion follows native image layout, zoom transforms and scroll offset; a viewport anchor maps its result into the figure. Coalesce finite, deduplicated post-layout updates and refresh on asset identity changes.
- Preserve labels, feature dialogs, pinch zoom, native tap-versus-drag cancellation and fullscreen controls. Whole-body note includes entry/plate context. Independent art and conceptual symbols prefer side notes. Explanation/note fonts become scalable 14/11 points. Remove active label/process bottom reservations introduced by the prior footer, while leaving default-compatible pure callout math intact.
- Process/retina notes target actual active native SwiftUI node anchors when available, falling back to the source generic art target otherwise. Specialized circulation/gas artwork remains unchanged. Retinal destinations/actions remain outside the figure; endocrine figures use 84...110-point images, reserved stage text and integrated scope.
- Aging notes reserve all stage labels with explanation and scope; human-study evidence remains outside and unchanged. ADME gets an interactive four-stage process with reserved current explanation and scope; linked structure rows no longer repeat the step description. Existing drug models/controls/curves remain unchanged.
- Villus and material-response explanations move into connected figures without changing numerical inputs, response formulas or their underlying diagrams.
- All catalogue data, references, personal-metric view, public selection/navigation cache, animation clocks, ownership/lifecycle controls and model kernels remain unchanged. No localization delta, version bump or IPA.

## Verification limits

Only source/resource/project/grammar/whitespace checks are available here. Added Swift fixture sources cover 580/280 thresholds, capped widths, short-window fallback, overlay bounds, aspect-fit subject mapping, clamped leader endpoints and backward-compatible pure callout inset math. They were NOT executed.

Windows has no Xcode. No Swift type checking, XCTest, simulator/device, native layout/coordinates/clearance, font measurement, animation timing, alert gestures, playhead-retention interaction, moving pixels, screenshots, full-catalogue device sweep or IPA validation is claimed. The original Android device checks and reported results were reviewed as source references only, not reproduced as iOS evidence.

Historical source contracts explicitly accept the newer connected-note layout and matched two-line probes, while freezing the unaffected numerical, diagram, playback/lifecycle, resource and navigation kernels. Historical port manifests describe those original revisions, not a claim that superseded footers remain active.

## Review scope

The formal PR base is `main`, but this branch cumulatively includes preceding unmerged iOS work through #4522. It is NOT an independent Android #4446 main diff. Review this port against the exact incremental base above; integrate predecessors in order or deliberately reconstruct integration. The entire Android backlog is still in progress.
