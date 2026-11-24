# Android #4439: synchronized lesson scenes and mechanism detail

## Exact source and scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4439
- Merge: `eef7fd41df84c075cbc0ba046cca6ab6a5b59bf7`.
- Incremental iOS base: `c4913f5c79b0aee7989774ae2f8b3e9a972257f7` (iOS PR #4515).
- One source hash and explicit disposition for each of the twenty original changed files in `ANDROID_4439_SOURCE_INVENTORY.json` and `ANDROID_4439_PORT_COVERAGE.json`.
- Seven production Kotlin changes ported, four device/helper sources reviewed as references, eight XML files imported as nineteen exact bilingual pairs, Android version-only change not copied.

## Native implementation

- Scene title, art and chapter/caption now share one frame above timeline and previous/play/next/more controls. Reserve the longest wrapped chapter and caption at the current width and Dynamic Type size; hidden layout text is excluded from accessibility.
- Pause before the more menu. Chapter picker seeks and closes, reset seeks zero, evidence opens the original scope and a separate reference list. Existing monotonic five-second chapter clock, reduced-motion sampling, ownership and disappearance pause code are retained byte-for-byte.
- All entry kinds use three compact semantic tabs: Structure, Function, Metrics. Structure-layer and short course selectors use the same compact control; long course lists retain their menu.
- System/organ models stay inline. Other numerical models use a native standalone navigation destination with Function highlighted; native Back returns to Function, or a compact tab selects its destination. Pause before snapshotting, retain lesson/input state, and retain research scroll restoration in both destinations.
- Remove repeated description/principle/hotspot art from course-backed Function pages; keep the fallback for entries without lessons. Structure alone owns anatomical sources/art notes. Inline and standalone numerical models retain their own evidence.
- Add the original graded inhibitory/excitatory trace, threshold, sequential sodium/potassium gates, calcium entry, receptor binding/opening/clearance, and pulmonary diffusion membrane cross-section. Other synaptic courses, respiratory chapters, numerical kernels and personal metrics are not rewritten.
- Immutable #4388 catalogue snapshot plus a pinned, idempotent #4439 overlay: two choice titles and one additional synaptic action-potential reference. Same 138 stories, 643 chapters and 313 routes; 321 references. Existing snapshot importers remain reproducible.

## Verification limits

Source/resource contracts, changed Swift grammar parsing, project registration and whitespace checks only. Added Swift fixture sources for catalogue preservation, graded potential and standalone return state; these fixtures have NOT been executed. Windows has no Xcode: no Swift type checking, simulator/device/XCTest run, native screenshots, pixel/gesture/VoiceOver acceptance or IPA is claimed.

Historical source audits are deliberately adapted only where this PR supersedes the old layout: verify the unchanged clock/lifecycle tail rather than freezing the entire player; verify three compact tabs/menu-owned transcript rather than obsolete segmented controls/inline outline. Drug/comparison/aging kernels, patient-metric privacy and restoration sanitizers remain guarded.

## Review dependency

The GitHub PR base is `main`, and the branch cumulatively includes earlier unmerged iOS work through #4515. It is NOT an independent twenty-file diff against main. Review this port using the exact incremental base above; merge predecessors in order or use a deliberately reconstructed integration branch. Do not infer native acceptance, all-PR completion, or CI approval from GitHub mergeability.
