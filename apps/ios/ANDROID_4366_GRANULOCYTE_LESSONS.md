# Android #4366: Three Independent Granulocyte Lessons

## Review Scope
- Ports Android #4366 at `3aa202bc663c6d15bc8085a6af965b461f620899`.
- Formal non-draft PR, base main. Predecessor iOS #4487 is merged; synchronize latest main before publication.
- New scope: two painted plates, four recalibrated features, three native lesson renderers, shared playback integration, bilingual scope/stage labels and scoped public Agent context.
- iOS only. No Android/Desktop edits, version bump, anatomy graph/model equations, personal-health storage or IPA changes.

## Implementation
- Uses source-identical transparent 1254-square eosinophil and basophil PNGs; retires obsolete generated PDFs. Retains existing neutrophil and macrophage artwork.
- Adds independent SwiftUI Canvas lessons: neutrophil vessel migration/exit and uptake; eosinophil contact and granule release; basophil mediator release and local vessel response.
- Preserves source geometry, colors, smoothstep motion, shared phase, four stages and restored deterministic playhead. Existing controls/timer handle background, reduced motion, pause and rewind; no second clock.
- Hides duplicate static artwork and bottom playback controls on these simulation pages.
- Imports four exact strings in each language. The stage accessibility label remains localized. Teaching scope is added only for the matching owner with active synthetic simulation on Simulation/Physiology screens; Values remains excluded.
- Updates both current and legacy public-question paths. No real measured lengths/times are inferred from the diagrams.
- Registers the new Swift source in the app target. Legacy immune import now preserves four current painted assets and eight remaining original vectors.

## Verification
- New pinned granulocyte audit passes: exact PNG bytes, dimensions, transparent corners, four opaque calibrated anchors, eight localized values without duplicate keys, unchanged remaining metadata, source motion formulas and native integration points.
- Existing immune and #4365 painted-innate audits pass: 12 plates, 25 local features and 30 retained vector paths.
- Legacy immune regeneration completed without changing retained vector resources.
- iOS project, module-settings, frozen base resource/i18n and whitespace checks pass. Eight changed/new Swift files parse under both conditional grammar branches; this is not type checking.
- Both new resource images visually inspected. These previews are not native app screenshots.
- Added XCTest source for three independent lesson geometries, stage boundaries, rewind consistency, label validation, finite phase handling, owner/screen-scoped prompts and 35 bitmap assets (119 canonical anchors plus eight innate local-feature pixel checks).
- XCTest not executed, as requested. Windows has no Xcode: native compilation, Asset Catalog processing, Canvas output at device sizes and actual VoiceOver/device acceptance remain unverified. No IPA generated.
