# Android #4384 iOS Scope Audit

Upstream: https://github.com/galaxyssi/GalaxySSI/pull/4384
Pinned source: `ab78711d467c013444883dbaeca23c39a601c875`.
Reviewed main: `bcc2d4c0fc9526d2b047741a3d47f3cece3d9c2b`.
This is a source-level implementation review, not native UI or build acceptance.

## Complete Source Inventory

The inventory contains 387 unique source paths and SHA-256 hashes:
113 production Kotlin files, 61 vector resource changes (including two deletions),
two original PNGs, 100 English resource files, 100 Chinese resource files,
five Android device-test files, four unit-test files, one Android build file,
and one Android architecture document.

All 81 renderer files are itemized in ANDROID_4384_PORT_STATUS.md with dedicated
native drawing paths, rather than generic substitute pictures. The other 32
production Kotlin files are accounted for below. The table is a scope index;
the checks and limitations below qualify its evidence.

| Android Source Group | Native iOS Counterparts / Evidence |
| --- | --- |
| AgentContext | AgentContext, FunctionContext and AgentHandoff; owner/current-course/current-chapter and research/Values gating checks |
| BeatStage, BreathingStage, DigestionStage, NephronStage, SoundStage, VisionStage, GanglionRelayAssignment | Kotlin-evaluated catalogue and dedicated Heartbeat, Breathing, Digestion, Nephron, Hearing, Vision and Ganglion scenes; per-entry initial phases retained |
| AutonomicNervesPlate, CartilageOverviewPlate, LigamentsPlate, PlacentaPlate, SynovialJointPlate, TissueContextPlates | Original Kotlin declarations evaluated into FunctionStructures; 54 plates/177 local features/27 canonical links |
| BloodDefenseView, GranulocyteView, ImmuneLinkView, PhagocytosisView, CellSceneView | Existing dedicated native scenes shared with CellFunctionView; four-stage source motion, fitting and original painted cells |
| FunctionArt, FunctionPlayer, FunctionState, FunctionStory | FunctionArtwork, Viewport, Player, Catalogue, Panel and State; all 101 courses, independent live/persisted phase and lifecycle controls |
| GutSections, Plates, SensoryPlates | GutSections, SectionLesson, FunctionStructures, atlas default/context lookup, Artwork and related Function destinations |
| Physiology, PhysiologyPanel, PhysiologyText | Matching native models/controls/results/text; eight added input specs, eleven owner routes, explicit units and references |
| MaterialResponseView | MaterialResponseView and Drawing; linked diffusion, compression and bending diagrams |
| SweatView | Existing SweatView and Homeostasis drawing; source change only extracts the unchanged eccrine duct path, checked against the retained native path |
| HealthBodyAtlasActivity | AtlasState, Detail, FunctionPanel, RelatedRow and AgentHandoff; course selection, restoration, previews, navigation and question snapshots |

The Android APK version bump is platform-specific and is not copied into the
iOS application version. Android instrumentation classes are not shipped in
iOS. Applicable contracts are represented by source/resource audits and added
XCTest source; no XCTest execution is claimed. The Android architecture notes
are reflected in the iOS port ledger and this audit.

## Resource And Functional Checks

- Catalogue: 101 courses, 491 chapters, 226 references, 268 owner routes.
- Text: 3127 exact source values in each of English and Chinese; zero inherited English fallback values in the Chinese Function table.
- The changed relationship heading uses the new Function value while retained BodyAtlas values remain compatible.
- Resource coverage: all 59 added/modified SVG identities resolve to imported iOS art; both deleted SVG identities resolve to original square PNGs.
- Eight PDF cohorts check 82 plates, 999 exact source paths and 276 gradients, including retained plates. Ordered affine matrices, RGB and independent fill/stroke alpha are checked in PDF drawing state.
- Teeth and jejunum retain source PNG bytes, eight recalibrated features, two links and square 360-unit section bounds.
- All 111 related Function links select the target course/tab before navigation without resetting stored target phases.
- Three quantitative models retain source ranges, equations, unit conversions, companion values and controls-before-chart ordering; 63 analytic boundary combinations checked.
- Public Agent preview consumes the current owner-bound Function snapshot in both build branches; unrelated research/Values screens do not gain Function context.
- Current-window height policy and delegated cell-scene heights are wired without a global-screen assumption.

## Verification Performed

- Complete 387-file source hash/catalogue audit.
- Full PR Swift grammar: 489 added/modified files, two preprocessed branches.
- All 83 selected source/resource audit entry points and five integration audits.
- Additional original cell-context audit, including the unchanged sweat duct.
- Project structure and eight module-setting subset checks.
- Full PR whitespace check and confirmation that changes stay under apps/ios.
- Latest fetched main is an ancestor; no unmerged predecessor code is required.

## Not Verified

Windows has no Xcode. Swift type checking, Metal compilation, app linkage,
simulator/device rendering, native Path sampling accuracy, VoiceOver behavior
and pixel acceptance remain unverified. Added XCTest source was not executed.
No IPA was generated and no CI bypass was added. These checks must not be
reported as successful native tests or a device-certified parity claim.
