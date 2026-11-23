# Android #4353: iOS Alimentary Sections and Villus Geometry

## Review Scope
- Ports Android #4353 at `eb17db473412f018fe6b67eb364bdbe482210b5b`.
- Base `main` includes predecessor iOS #4475. Only this port is new review scope.
- iOS only; no Android/Desktop changes, version bump, IPA or personal health-storage writes.

## Implementation
- Fourteen existing alimentary organs have independent four-stage mechanisms, original vector illustrations, 47 local explanatory features and 29 canonical anatomy links.
- Esophagus, stomach, small intestine, duodenum, large intestine and cecum have 24 representative stage tracks, including the original straight, quadratic and cubic segments.
- Shared section lesson/view types serve both gut and lymphatic courses. Existing lymphatic aliases preserve callers and source fixtures; the single lifecycle-managed playback timer is unchanged.
- Current feature titles and scoped notes follow matching selected entry/stage into public Agent context. The unfolded small-intestinal map, front-view large-intestine orientation and appendix-opening caveat remain owner-specific.
- Small intestine and jejunum alone receive an adjustable villus geometry model: area ratio = 1 + density * 2 * pi * radius * height. Separate top/side views preserve source positions, dimensions, controls-first ordering, visible caption, 3-decimal radius precision and accessible description.
- Geometry is an ideal 1 mm2 patch, not measured or personal absorption. Zero villi gives ratio 1; no folds, microvilli or transport are inferred.
- Both languages have all 192 new source strings with platform escapes/placeholders adapted.
- Catalogue: 313 entries and 192 mechanisms. Existing cell/fragment artwork and identities are unchanged.

## Verification
- `node apps/ios/tools/check-body-atlas-gut-sections.cjs`: source parity for graph, 14 plates, 99 original paths, features, links, stage maps, 24 tracks, scope notes and 384 localized values.
- Previous `check-body-atlas-lymph-organs.cjs` also passes its frozen Android #4352 composition.
- `npm run check:ios` and `node apps/ios/tools/check-atlas-module-flags.cjs` pass static structure/settings audits.
- Swift grammar audit: 15 changed Swift files, both conditional branches. Not Swift type checking.
- All 14 PDFs rendered with Poppler; 76 feature/link anchors are nonblank; contact sheet visually inspected.
- Added XCTest source for geometry fixtures, boundaries/ownership/precision, lesson navigation, track endpoints, independent state restoration and Agent screen/owner isolation. Not executed, as requested.
- Windows has no Xcode: native compilation, device/simulator animation, VoiceOver and UI acceptance remain unverified. No IPA generated.

## Reproduction
Import and parity tools require `pdf-lib` and/or `xml-js` through `NODE_PATH`; source files are read from the pinned Android git commit.
