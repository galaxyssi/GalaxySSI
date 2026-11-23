# Android #4362: System Overview Artwork

## Review Scope
- Ports Android #4362 at `5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2`.
- Formal non-draft PR targeting main. Predecessor iOS #4483 (Android #4361) is merged; synchronized with main at `9829bc90f` before publication. Only this four-plate increment remains in the diff.
- iOS only. No Android/Desktop edits, version bump, graph/model changes, new strings, personal-health changes or IPA.

## Implementation
- Replaces the nervous-system PDF with the byte-identical transparent 1024-by-1536 posterior PNG and its five calibrated landmarks. Keeps dedicated brain-page precedence and existing nerve navigation.
- Converts the updated cardio, testicular and ovarian overview paths into native PDF gradients: 39 original paths, 18 gradients, unchanged 420-by-560 / 420-by-400 viewports.
- Keeps original overview/callout provenance and records the four-plate artwork revision separately.
- Reuses the existing PDF gradient converter. The legacy overview importer now regenerates current artwork rather than restoring the obsolete nervous PDF or flat vectors.
- Updates pinned source/resource audits. Adds XCTest source for five brain/nerve color-neighborhood checks and expands bitmap fixtures to 30 assets / 113 canonical anchors.

## Verification
- Current system audit passes: exact PNG bytes, dimensions, transparent corners, opaque landmarks, brain/nerve color neighborhoods, all 23 system markers and 54 preserved routes.
- Three PDF audits pass: exact gradient colors/coordinates, viewports, native shading and no embedded raster substitutes.
- Independent Android SVG versus generated PDF raster comparisons pass: mean absolute channel errors 0.3384, 0.4253 and 0.7324 (0-255 scale). Three rendered plates visually inspected; these are resource renders, not app screenshots.
- Existing six painted-overview audit, iOS project check, module settings audit and frozen base resource/i18n audit pass.
- Changed Swift test source parses under both conditional grammar branches. This is not Swift type checking.
- XCTest not executed, as requested. Windows has no Xcode: native build, Asset Catalog compilation, actual UI layout and device/accessibility acceptance remain unverified. No IPA generated.
