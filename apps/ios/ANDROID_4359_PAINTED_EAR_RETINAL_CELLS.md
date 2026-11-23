# Android #4359: Painted Ear and Shaded Retinal Cells

## Review Scope
- Ports Android #4359 at `b513fe5023b8699e4e64e1f914f09be98ddeeacb`.
- Formal non-draft PR targeting `main`; predecessor iOS #4480 (Android #4358) is merged.
- Only this increment is new scope. iOS only; no version bump, graph/model/string changes, personal health storage, Android/Desktop changes or IPA.

## Implementation
- Uses the byte-identical 1536-by-1024 transparent painted ear in structure, fullscreen and simulation; retires the old PDF and its vector-only asset flag.
- Recalibrates all five ear navigation markers, four highlighted features and four source air-conduction paths to the 420-by-280 logical canvas.
- Final path follows the auditory nerve to (411, 135), separate from the oblique auditory tube.
- Shades six retinal cell/tissue diagrams: AII amacrine, bipolar, cone, ganglion, rod and retinal pigment epithelium. Keeps all 49 original paths, circuit links and quantitative models; emits 17 real PDF gradients, not rasterized substitutes.
- Keeps the previous eye/hair-cell/retinal-section PDFs byte-stable. Their audit now covers the three retained vectors, while ear rendering is checked against its new bitmap revision.
- Extends the shared importer with `--retinal-cells`; the legacy ear import entry delegates to the painted-ear importer instead of recreating the retired asset.
- Image XCTest fixtures cover 25 bitmaps and 105 canonical anchors; added ear feature/path coverage and the nerve endpoint colour assertion.

## Verification
- `check-body-atlas-painted-ear.cjs`: exact Android PNG bytes, 3:2 dimensions, transparent corners, five exact opaque markers, four features, 52 arc-length route samples on the painted anatomy and ochre nerve endpoint.
- `check-body-atlas-sensory-sections.cjs --retinal-cells`: six PDFs, 49 source paths, 17 native PDF gradients with exact stops/coordinates, no raster XObjects and exact current ear routes/features.
- Default sensory-sections audit also passes for the three retained #4358 vectors (46 paths / seven gradients).
- Local Poppler render versus independent Sharp SVG transcription at 2x: mean absolute channel differences on the 0-255 scale are 0.675 (AII), 0.388 (bipolar), 0.080 (cone), 0.229 (ganglion), 0.135 (rod), 0.382 (RPE). Contact sheet visually inspected; these are not native app screenshots.
- `npm run check:ios`, `check-atlas-module-flags.cjs` and frozen base resource/i18n checks pass.
- Three changed Swift files pass grammar parsing under both conditional branches, not Swift type checking.
- XCTest source updated but not executed, as requested. Windows has no Xcode: native build, launch, device/simulator animation, accessibility and UI acceptance remain unverified. No IPA generated.

## Reproduction
Tools require `pdf-lib`, `xml-js`, `sharp` and, for arc-length sampling, `svg-path-properties@2.0.0` through `NODE_PATH`. The additional path-measurement dependency was installed outside the repository in a temporary audit directory; it is not an app dependency.
