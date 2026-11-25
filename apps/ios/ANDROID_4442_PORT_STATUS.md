# Android #4442: shared physiology scene frames

## Exact source and dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4442
- Merge: `d1b5f1d3c5abba4c086157d358e712cedebc9487`.
- Incremental iOS base: `f32614eb269ef1f34e2f1449d384410d8d99eaeb`, PR #4518.
- Eleven original changed files: five production Kotlin, four Android device references, one JVM reference, one Android version-only change. Every original file has a hash and explicit disposition in the source inventory and coverage JSON.

## Native implementation

- Reuse one framed scene surface and longest-wrapped-caption component for guided lessons and physiology models. Hidden sizing text is excluded from accessibility; current stage labels wrap at the current width and Dynamic Type size. No fixed single-line approximation.
- Group model title, native diagrams, current stage, playback and position in the model frame. Standalone specialized models retain controls before their diagram; inline models use controls after it. Germline stage stays before the counts. Endocrine and retinal diagrams retain their own stage presentation instead of adding a duplicate generic caption.
- Replace the generic inline 2x2 process layout with a horizontal numbered chapter strip, 48-point targets, current-stage selection and complete accessibility labels. Non-inline models retain the labelled 2x2 order. Specialized circulation/gas/endocrine/retinal diagrams keep their own navigation controls.
- Put supplementary notes, related immune destinations and source links in an initially collapsed inline evidence disclosure. Standalone supplementary notes remain visible outside the scene. Hoist existing child-owned notes via default-compatible view flags so neither links nor references are silently removed; other callers retain previous defaults.
- Remove the duplicate outer inline physiology source and keep it inside the evidence disclosure. Keep cardiac/ventilation parameters, every physiology model input, source destinations and drill-down callbacks. Pause before diagram navigation and artwork preview. Default model artwork uses the existing native pinch/slider zoom view.
- Retain exact numerical invocation, all reset/play/pause/parameter handlers, timer and lifecycle code. Preserve lesson metadata, state restoration, Agent context, personal metrics, all existing drawing kernels and qualitative/clinical boundaries.
- Source audit compares all 313 pinned Android entry IDs with native immutable lesson routes and all 138 registered renderer IDs. Added full-catalogue bilingual-caption fixture source; no new resources or iOS version bump.

## Verification limits

Source/resource contracts, grammar parsing, project registration and whitespace checks only. No Xcode on Windows: no Swift type checking, XCTest, device/simulator execution, native view containment, stable-height pixels, tap/gesture/VoiceOver certification, screenshots or IPA. Android's device and JVM tests are source references, not executed iOS evidence.

Historical audits deliberately check preserved renderers, exact playback/numerical handlers and current scene ordering rather than freezing the superseded flat layout. They continue to verify earlier resource deltas, model semantics, privacy and restore bounds. Source-level coverage is not native acceptance.

## Review scope

Formal PR base is `main`, but the branch cumulatively includes earlier unmerged iOS work through #4518. It is NOT an independent main diff for #4442. Review this port with the exact incremental base above; integrate predecessors in order or reconstruct integration deliberately. No completion claim for the entire Android backlog.
