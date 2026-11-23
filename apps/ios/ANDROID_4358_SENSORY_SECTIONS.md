# Android #4358: iOS Sensory Sections and Shaded Vector Artwork

## Review Scope
- Ports Android #4358 at `7e5841c21c313fd2ecee924e6805385e96a564a1`.
- Formal non-draft PR targeting `main`; predecessor iOS #4479 (Android #4357) is merged.
- Only this sensory increment is new review scope. iOS only; no version bump, graph/model changes, personal health writes, Android/Desktop changes or IPA.

## Implementation
- Restyles ear and eye cross-sections, cochlear hair cell and retinal layers, retaining all 63 original paths.
- Importer emits real PDF vector paths and 11 linear/radial gradient shadings, with source stops, positions, clipping, opacity and strokes. No raster flattening.
- Adds a shared lesson factory for the ear and retina without replacing the structure view's original anatomy markers.
- Ear: four source air-conduction routes and four feature highlights on a 460-by-280 canvas. The scope note explicitly separates playback from real speed, strength and frequency.
- Retina: rod, relay layer, cone and ganglion highlights follow the same stage/phase as the existing circuit nodes. No circuit topology, quantitative equation or model-input change.
- Shared rendering uses per-lesson width; legacy gut/lymph routes retain their 360-unit validation. Wide ear routes are accepted only when the declared width accommodates them.
- Uses existing lifecycle-managed playback and per-entry restoration; avoids duplicate retinal playback controls.
- Adds three resource strings in each supported language and preserves selected-feature context isolation.

## Verification
- `node apps/ios/tools/check-body-atlas-sensory-sections.cjs`: four PDF media boxes, 63 source paths, 11 native PDF gradient resources with exact functions/coordinates, no raster XObjects, four exact ear routes/features and six localized values.
- Local Poppler PDF rendering compared with Sharp rendering of an SVG transcription of the same source paths/gradients at 2x: mean absolute channel errors 0.526 (ear), 0.361 (eye), 0.548 (hair cell), 0.941 (retina), on a 0-255 scale. Contact sheet visually inspected. Not native app screenshots.
- Prior bitmap-final, lymphatic and gut source/resource audits also pass.
- `npm run check:ios`, `check-atlas-module-flags.cjs` and the frozen base resource/i18n audit pass.
- Six changed Swift files pass grammar parsing under both conditional branches. Not Swift type checking.
- Added XCTest source for wide-canvas bounds, source endpoints, restored independent stages/model inputs, preserved structure markers, layer order and context screen/owner isolation. Not executed, as requested.
- Windows has no Xcode: native build, Asset Catalog compilation, launch, animation pixels, device/simulator operation and VoiceOver/UI acceptance remain unverified. No IPA generated.

## Reproduction
The import/audit tools use `pdf-lib` and `xml-js` through `NODE_PATH`. PDF rendering uses Poppler; independent SVG rendering uses Sharp.
