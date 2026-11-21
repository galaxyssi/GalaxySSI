# Android #4322: Native Body Atlas

## Source and Scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4322
- Isolated implementation commit: `17cc2c33b` (merge `40d917731224fff104ff9ceb21e4bb7461ce2703`).
- This PR does not repeat Android #4321 conversation actions or its unrelated Desktop test changes.
- Main Health Center body entry now opens the atlas. The older six introductory lessons remain accessible from its whole-body page.
- Target remains iOS 15 and later. Native navigation, segmented controls, scoped Health theme, SF Symbols, and Dynamic Type are used rather than Android layout classes.

## Feature Mapping

| Android surface | iOS implementation |
| --- | --- |
| HealthBodyAtlas and bundled catalogue | `GalaxySSIHealthAtlas.swift`, frozen `body-atlas/body-atlas.json` |
| Whole body, systems, organs, cells | `GalaxySSIHealthAtlasState.swift`: 14 categories, 158 structures, 105 cell types/subtypes and one platelet fragment; all-word localized search, system filters, 24-entry pagination |
| Structure/function/values/simulation | `GalaxySSIHealthAtlasDetail.swift`: canonical relationships, associated process attribution, sources, scoped personal measurements |
| Labeled illustrations | `GalaxySSIHealthAtlasArtwork.swift`: original whole-body, external-heart and beta-cell PNGs; numbered accessible hotspots, label list, layers, native pinch/pan, zoom/reset/fullscreen |
| Teaching process controls | `GalaxySSIHealthAtlasSimulationPanel.swift`: 20 four-stage sequences, playback/seek/steps/speed/reset, pauses on background/disappear and Reduce Motion |
| Physiology, pharmacology, aging | `GalaxySSIHealthAtlasResearch.swift`: shared physiology inputs, ADME links, normalized elimination curve, four aging themes and source/evidence limits |
| Personal values | Existing `GalaxySSIHealthTrendView`: associated metric allowlist, latest actual reading/source, week/calendar-month/calendar-year, chart audit and record navigation; existing consent and scoped Agent analysis flow retained |
| Ask Agent | `GalaxySSIHealthAtlasAgentHandoff.swift`: public-only preview, new `body-atlas` conversation, owner/conversation-bound in-process capability, one use, 120 seconds, maximum 8 pending |
| Selection restoration | Bounded SceneStorage of public entry/tab/research/teaching/metric-period/zoom choices only; no observations, files, source records or decrypted chart data are serialized |
| Languages | Dedicated English and Simplified Chinese `BodyAtlas.strings` tables, 1,026 keys each; Android XML quoting and format placeholders converted |

## Boundaries

The frozen catalogue and AI-generated illustrations have the same teaching limitations as Android. This is not a complete anatomy ontology, diagnostic image set, individual organ simulator or validated personal health score. Most entries deliberately have no dedicated illustration; related external-heart art is identified as context, not an isolated image of each structure. Public reference links are online; the catalogue, teaching images and model calculations are bundled for offline use.

Only cardiac output and minute ventilation have numeric teaching equations. The drug explorer is a normalized single-compartment elimination example, with no drug identity, dose, patient parameters, concentration thresholds or treatment recommendations. Other processes are qualitative. The aging section describes research themes, not personal biological age or anti-aging efficacy.

Public teaching questions cannot read a Health archive or inherit composer attachments. Personal trend analysis continues through the existing explicit review/disclosure path. Existing trend lifecycle handling drops chart/readings/analysis state when leaving the foreground.

## Verification

- `npm run check:ios`: static project structure check.
- `node apps/ios/tools/check-body-atlas.cjs`: bundled graph, counts, translation keys/placeholders, Android quoting and PNG metadata audit.
- Swift grammar parsing of new atlas sources/test source and changed trend view.
- `git diff --check`.
- Source corpus and PNG blobs compared byte-for-byte with the isolated Android commit; changed iOS text files audited for Chinese placement. The shared i18n guard now recognizes only the new `zh-Hans.lproj/BodyAtlas.strings` table in addition to the existing table, with a regression fixture added but not executed.
- Focused XCTest source added for graph/resources, filters, metric allowlist, calendar/leap-day windows, teaching equations, restoration and one-use handoff. **Not executed**, per request.
- No Xcode build, simulator/device run, visual UI parity certification, IPA generation or XCTest execution was performed on Windows. Native layout, pan/zoom, accessibility, actual private trend navigation and Agent transport still require an Apple build/runtime before claiming device validation.

The PNGs and JSON are unmodified blobs from the isolated Android commit. Android's bundled Lucide/Feather attribution is retained in `body-atlas/body-atlas-lucide.txt`; iOS uses native SF Symbols for category controls rather than importing Lucide vector paths.

The existing iOS encrypted archive/trend implementation is reused rather than introducing Android's SQLite repository. Atlas filters and Agent disclosure are scoped to selected metrics/periods, but this PR does not claim to replace the underlying encrypted archive with Android's indexed storage engine. Native zoom/fullscreen and navigation follow iOS conventions rather than pixel-identical Android widgets.

## Additive Resource Contract

The atlas optionally consumes the bundled `HealthAtlasOrganPlates` data asset. With no pack, the original 278-entry catalogue and three illustrations remain unchanged. A pack can only add uniquely identified entries at existing anchors and prepend explicit relationships; schema, IDs, markers, coordinates, image availability and normalized aspect ratios are validated before opening the atlas. It cannot load a network document or executable code.

This allows the following Android #4323 image/metadata increment to be a separate, independently buildable main-based PR without duplicating this foundation. The pack's English strings are bundled with its metadata; Chinese strings use the existing `Localizable.strings` table. Base XCTest counts explicitly load the frozen base without extensions. Layer controls navigate actual systems/children/cells/visible markers, and fullscreen retains the plate caption and accessible labels.

Asset packaging follows Apple's [Data Set Type specification](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/DataSetType.html). An absent optional pack is supported; an installed but malformed pack fails catalogue loading rather than silently presenting incomplete anatomy.
