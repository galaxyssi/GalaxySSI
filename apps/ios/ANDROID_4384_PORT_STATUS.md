# Android #4384 Port Status

Source: `ab78711d467c013444883dbaeca23c39a601c875`.
This is an in-progress implementation, not a completed parity claim or a ready PR.
Keep one final iOS PR for the whole Android #4384 increment. Do not move on to #4385 until this source scope is covered.

## Completed Foundation
- [x] Inventory all 387 changed source paths, including deletions, with pinned SHA-256 hashes.
- [x] Export 101 stories, 491 chapters, 226 references and 268 owner routes by evaluating source catalogue/stage declarations with Kotlin.
- [x] Preserve first-owner precedence, multi-course choices, related lessons and per-entry initial chapter phases.
- [x] Add iOS catalogue decoding, bounds/source validation and isolated per-owner course/phase selection model.
- [x] Register the new Swift source and data asset. Add XCTest source for catalogue and selection contracts; XCTest not executed.

## Remaining Integration
- [x] Import 3127 source-referenced chapter/caption/control/structure/scope strings per language into the dedicated AtlasFunction table; no English fallback in Chinese. Preserve existing BodyAtlas precedence, with new-table fallback for new structure keys.
- [ ] Complete Function-tab player integration across all source courses. Core player, course selector, controls, source links, phase restoration and lifecycle are wired for the first supported course (GLUCOSE); all other courses still await their dedicated renderers.
- [x] Connect optional persisted Function selections without changing quantitative simulation selections. Keep live animation phase outside published/serialized state; pause/exit commits it, while question snapshots read current live phase. Corrupt Function-only storage does not discard unrelated selections.
- [ ] Import all new/revised illustration resources and cutaway geometry.
- [ ] Port additional structure views, canonical/feature routing and related Function destination navigation.
- [ ] Port ventilation, diffusion and skeletal model changes and their parameter/result UI.
- [ ] Update Agent public context and fallback question paths with the active Function lesson/chapter.
- [ ] Complete every renderer below, preserving chapter-specific geometry and motion rather than generic stand-ins.
- [ ] Static source/resource/grammar/project checks across the completed scope, then review and publish one formal main-based PR.
- [ ] Synchronize any newly merged predecessor PRs and update dependency scope before publication.

## Renderer Parity
Next renderer: port HealthAtlasBeatStage and HealthAtlasHeartbeatView together, then continue the source-order list. Only GLUCOSE is currently enabled in FunctionRendering; do not broaden that registry before the corresponding native renderer is implemented.

- [x] `HealthAtlasUptakeView` — native 344-unit source geometry, four signal paths, relay thresholds, membrane fusion and glucose transport; source/resource/grammar checks only, native pixels unverified.
- [ ] `HealthAtlasHeartbeatView`
- [ ] `HealthAtlasBreathingView`
- [ ] `HealthAtlasHearingStoryView`
- [ ] `HealthAtlasNephronStoryView`
- [ ] `HealthAtlasDigestiveStoryView`
- [ ] `HealthAtlasVisionStoryView`
- [ ] `HealthAtlasMovementStoryView`
- [ ] `HealthAtlasLymphImmuneStoryView`
- [ ] `HealthAtlasInsulinStoryView`
- [ ] `HealthAtlasHomeostasisStoryView`
- [ ] `HealthAtlasSignalStoryView`
- [ ] `HealthAtlasBarrierStoryView`
- [ ] `HealthAtlasGameteStoryView`
- [ ] `HealthAtlasChemicalSenseStoryView`
- [ ] `HealthAtlasMotionSenseStoryView`
- [ ] `HealthAtlasOcularStoryView`
- [ ] `HealthAtlasAirwayStoryView`
- [ ] `HealthAtlasEndothelialStoryView`
- [ ] `HealthAtlasPlateletStoryView`
- [ ] `HealthAtlasCartilageStoryView`
- [ ] `HealthAtlasSmoothMuscleStoryView`
- [ ] `HealthAtlasTendonStoryView`
- [ ] `HealthAtlasSurfactantStoryView`
- [ ] `HealthAtlasIntestinalAbsorptionStoryView`
- [ ] `HealthAtlasKneeStoryView`
- [ ] `HealthAtlasCardiacSignalStoryView`
- [ ] `HealthAtlasRedCellStoryView`
- [ ] `HealthAtlasSalivaStoryView`
- [ ] `HealthAtlasVenousReturnStoryView`
- [ ] `HealthAtlasHairCycleStoryView`
- [ ] `HealthAtlasUrineRouteStoryView`
- [ ] `HealthAtlasPleuraStoryView`
- [ ] `HealthAtlasCalciumFeedbackStoryView`
- [ ] `HealthAtlasMammaryStoryView`
- [ ] `HealthAtlasCerebellumStoryView`
- [ ] `HealthAtlasMelaninStoryView`
- [ ] `HealthAtlasLarynxStoryView`
- [ ] `HealthAtlasAstrocyteStoryView`
- [ ] `HealthAtlasSplenicFilterStoryView`
- [ ] `HealthAtlasThymusStoryView`
- [ ] `HealthAtlasBrainstemRhythmStoryView`
- [ ] `HealthAtlasFibroblastStoryView`
- [ ] `HealthAtlasArterialStoryView`
- [ ] `HealthAtlasChondrocyteStoryView`
- [ ] `HealthAtlasAdrenalMedullaStoryView`
- [ ] `HealthAtlasGastricAcidStoryView`
- [ ] `HealthAtlasMarrowStoryView`
- [ ] `HealthAtlasCoronaryStoryView`
- [ ] `HealthAtlasPodocyteStoryView`
- [ ] `HealthAtlasEndometriumStoryView`
- [ ] `HealthAtlasCranialReflexStoryView`
- [ ] `HealthAtlasSebaceousStoryView`
- [ ] `HealthAtlasCerebralSensorimotorStoryView`
- [ ] `HealthAtlasAutonomicRelayStoryView`
- [ ] `HealthAtlasGastricChiefStoryView`
- [ ] `HealthAtlasTonsilStoryView`
- [ ] `HealthAtlasAcinarEnzymeStoryView`
- [ ] `HealthAtlasNailStoryView`
- [ ] `HealthAtlasSinusDrainageStoryView`
- [ ] `HealthAtlasToothMasticationStoryView`
- [ ] `HealthAtlasMesangialStoryView`
- [ ] `HealthAtlasIntercalatedStoryView`
- [ ] `HealthAtlasClubCellStoryView`
- [ ] `HealthAtlasDuctBufferStoryView`
- [ ] `HealthAtlasCholangiocyteStoryView`
- [ ] `HealthAtlasPinealStoryView`
- [ ] `HealthAtlasThoracicFrameStoryView`
- [ ] `HealthAtlasMicrogliaStoryView`
- [ ] `HealthAtlasEpendymalStoryView`
- [ ] `HealthAtlasDeltoidStoryView`
- [ ] `HealthAtlasScapularRotationStoryView`
- [ ] `HealthAtlasGanglionRelayStoryView`
- [ ] `HealthAtlasLigamentGuidanceStoryView`
- [ ] `HealthAtlasPlacentalExchangeStoryView`
- [ ] `HealthAtlasRectusFlexionStoryView`
- [ ] `HealthAtlasObliqueRotationStoryView`
- [ ] `HealthAtlasErectorSupportStoryView`
- [ ] `HealthAtlasGlutealExtensionStoryView`
- [ ] `HealthAtlasGutLymphoidStoryView`
- [ ] `HealthAtlasCellFunctionArt`

## Verification Limits
Current foundation checks pass: all 387 source hashes, exported catalogue/route invariants, iOS project/module configuration, two changed Swift grammar branches and whitespace. This proves foundation consistency only, not renderer or UI parity.

Player checkpoint: dedicated source tables contain 3127 exact strings in each language; registry exposes only the implemented GLUCOSE course. Its UIKit/SwiftUI motion, four signal routes, relay nodes and membrane fusion are ported, but not run on a device. Generic chapter controls, lifecycle pause, references and separate live/persisted state are connected; no unsupported course is replaced by a generic picture.

The player does not serialize the entire atlas each frame. A non-published live phase cache supplies current question snapshots; pause/reset/exit commit the bound course phase. Dedicated Function decoding tolerates corrupt Function-only state without discarding other selection fields. New XCTest source covers timing, snapshots, restoration and uptake checkpoints; it has not been executed.

Kotlin evaluation is catalogue-data extraction with resource/constant stubs, not an Android build, renderer fixture or test run.
Windows has no Xcode. Do not claim Swift type checking, native compilation, device/simulator, VoiceOver or pixel acceptance.
No XCTest execution or IPA generation is requested.
