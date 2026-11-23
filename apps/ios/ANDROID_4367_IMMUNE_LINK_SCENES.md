# Android #4367: Tissue Recruitment and Immune Response Scenes

## Review Scope
- Ports Android #4367 at `20de8dd75a18c257e7a8fdba844511d3bd98c37d`.
- Formal non-draft PR, base main. Predecessor iOS #4488 is merged; synchronized main at `3ea3e7262` before publication. No preceding feature changes remain in the main-based diff.
- New scope: three painted plates/seven recalibrated features, three independent native lessons, canonical related-cell navigation, shared scene framing and public teaching-scope integration.
- iOS only. No version, anatomy graph/model equations, Android/Desktop, personal-health storage or IPA changes.

## Implementation
- Imports byte-identical transparent 1254-square monocyte, dendritic and plasma-cell PNGs and retires obsolete vector assets. Existing feature names/explanations remain unchanged.
- Adds recruitment/possible macrophage differentiation, material processing/T-cell antigen presentation, and plasma-cell antibody release scenes using the original source coordinates, colors and motion.
- Related rows navigate to existing macrophage, T-cell and B-cell pages and pause playback before navigation. Source and destination simulation selections remain independent.
- Shares the existing granulocyte lessons' 360-by-200 centered Canvas, four-stage easing, localized accessibility label and clipping. Retains landscape T/B-cell portrait proportions using the source's centered integer fitting rather than stretching them.
- Reuses shared simulation phase, persistence and lifecycle controls; adds no timer or separate playhead.
- Imports three exact teaching-scope strings per language and restricts them to matching owners on Simulation/Physiology pages in both public question paths.
- Registers both new Swift sources and updates legacy import/audits to preserve seven painted immune plates and five remaining original vectors.

## Verification
- New immune-link resource/source audit passes: exact PNG bytes, sizes, transparency, seven opaque anchors, six localized strings, unchanged remaining metadata, three canonical destinations and source motion/fitting integration.
- Existing immune, granulocyte and painted-innate audits pass. Original graph composition remains 313 entries / 192 mechanisms.
- Legacy immune regeneration leaves the five retained vectors unchanged (18 original paths).
- iOS project, module-settings, frozen base resource/i18n and whitespace checks pass. Ten changed/new Swift files parse under both conditional grammar branches; not Swift type checking.
- All three new resource images visually inspected. These are not native app screenshots.
- Added XCTest source for scene geometries, deterministic frames, shared stage/ease, canonical mappings, independent restored selections, square/landscape portrait fitting and owner/screen-scoped prompts. Bitmap fixtures now cover 38 images, 119 canonical anchors and 15 immune local-feature pixel checks.
- XCTest not executed, as requested. Windows has no Xcode: compilation, Asset Catalog processing, actual tap navigation/return, Canvas pixel output and VoiceOver/device acceptance remain unverified. No IPA generated.
