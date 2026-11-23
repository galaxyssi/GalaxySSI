# Android #4368: Core Painted Blood and Immune Scenes

## Review Scope
- Ports Android #4368 at `26b7b4395a27a74a3f9e3e45db9c46f217c505f9`.
- Formal non-draft PR, base main. Predecessor iOS #4489 (Android #4367) remains pending; continue without waiting, as requested.
- Review the new increment against #4489 head `90ff0f558`. Its existing scene/helper changes are inherited dependencies, not duplicate implementations or new #4368 scope. Both branches include main at `3ea3e7262`; synchronize after #4489 merges.
- iOS only. No version bump, Android/Desktop edits, anatomy graph/model equations, personal-health storage or IPA changes.

## Implementation
- Imports five exact transparent 1254-square painted resources: T, B, NK, megakaryocyte and platelet. Recalibrates ten local feature anchors and removes obsolete PDFs.
- Adds five separate four-stage lessons using the shared native Canvas/playhead: adaptive activation/expansion/outcomes, NK target response, megakaryocyte platelet release, and activated platelet recruitment/plug illustration.
- Preserves source geometry, colors, phase easing, portrait fitting and stage/accessibility labels. No second timer or separate animation state.
- Adds canonical related navigation to dendritic cells, plasma cells, platelet fragments and megakaryocytes; pauses playback before navigation. NK has no fabricated related destination.
- Keeps the platelet as an anucleate fragment in structure and catalog data; its lesson, teaching scope and restoration remain independent from the megakaryocyte precursor.
- Shares the existing related-row UI with immune-link scenes. All twelve immune-family images are now source-equivalent PNGs; legacy import delegates only current asset importers and cannot restore retired vectors.
- Imports five exact teaching scopes per language, including the platelet coagulation/treatment limitation. Both public Agent question paths restrict them to the matching owner and active Simulation/Physiology screens, never Values.

## Verification
- Current family audit passes for all 12 source PNGs, 25 feature coordinates/opaque anchors, dimensions, transparent corners, ten localized values, fragment identity and five native integration/motion definitions.
- Existing immune, painted-innate, granulocyte and immune-link audits pass. Frozen graph audit remains 313 entries / 192 mechanisms.
- Full immune importer regenerated all twelve current resources successfully. No unrelated image changes were produced.
- iOS project, module settings, frozen base resource/i18n and whitespace checks pass. Eleven changed/new Swift files parse under both conditional grammar branches; this is not Swift type checking.
- All five new image resources visually inspected. These are not app screenshots.
- Added XCTest source for independent frame/restoration state across five owners, shared stage/ease, adaptive clones, NK target radius, megakaryocyte release, platelet recruitment/fragment identity and owner/screen context restrictions. Bitmap fixtures cover 43 images, 119 canonical anchors and 25 immune local-feature pixel checks.
- XCTest not executed, as requested. Windows has no Xcode: native compilation, Asset Catalog processing, actual renderer pixels/rewind/tap navigation and VoiceOver/device acceptance remain unverified. No IPA generated.
