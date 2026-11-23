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
- [ ] Complete Function-tab player integration across all source courses. Core player, course selector, controls, source links, phase restoration and lifecycle are wired for thirty-one courses through nineteen dedicated renderers; other courses still await their dedicated renderers.
- [x] Connect optional persisted Function selections without changing quantitative simulation selections. Keep live animation phase outside published/serialized state; pause/exit commits it, while question snapshots read current live phase. Corrupt Function-only storage does not discard unrelated selections.
- [ ] Import all new/revised illustration resources and cutaway geometry.
- [ ] Port additional structure views, canonical/feature routing and related Function destination navigation.
- [ ] Port ventilation, diffusion and skeletal model changes and their parameter/result UI.
- [ ] Update Agent public context and fallback question paths with the active Function lesson/chapter.
- [ ] Complete every renderer below, preserving chapter-specific geometry and motion rather than generic stand-ins.
- [ ] Static source/resource/grammar/project checks across the completed scope, then review and publish one formal main-based PR.
- [ ] Synchronize any newly merged predecessor PRs and update dependency scope before publication.

## Renderer Parity
Next renderer: port HealthAtlasPlateletStoryView, then continue the source-order list. Thirty-one courses are enabled through nineteen dedicated renderers; do not broaden FunctionRendering before the corresponding native renderer is implemented.

- [x] `HealthAtlasUptakeView` — native 344-unit source geometry, four signal paths, relay thresholds, membrane fusion and glucose transport; source/resource/grammar checks only, native pixels unverified.
- [x] `HealthAtlasHeartbeatView` — five source stages, seven exact cubic routes, shared valve anchors and 24x24 deformable heart mesh; Metal plus equivalent CoreGraphics triangle fallback, native shader/pixels unverified.
- [x] `HealthAtlasBreathingView` — five source stages, original lungs/alveolus resources, whole/detail crossfade, reversible shared-trachea airflow, diaphragm movement, nine-curve blood path and opposing diffusion; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasHearingStoryView` — five source stages, 28x28 ear/hair deformation meshes, exact cochlea/nerve paths, source oscillation/packet timing, annotations and synaptic particles; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasNephronStoryView` — five source transport stages, thirteen exact line/quadratic/cubic routes, stage-specific flow counts and colors, proximal/distal capillary streams and original tall illustration; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasDigestiveStoryView` — two independent five-stage courses, seventeen exact motion routes, source bolus/mixing/squeeze/secretion/absorption/water-recovery rules, six dedicated vector PDFs (35 paths / 21 gradients) and original villus PNG; source/grammar checks only, native pixels unverified. Existing structure plates remain pinned until the structure migration.
- [x] `HealthAtlasVisionStoryView` — separate visual pathway and light-adaptation courses, six source routes including three converging rays, light-capture release threshold, rod/cone relative responses and source artwork; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasMovementStoryView` — separate muscle-motion and bone-remodeling courses, original nerve/tubule paths, fixed filament lengths, elbow rotation and changing muscle attachments, erosion/reversal/osteoid/mineralization scenes and native gradients; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasLymphImmuneStoryView` — separate lymph-return and antibody-response courses, source filling/holding/emptying inlet/outlet rules, continuous original node/duct paths and retained gradients, B/T/plasma source images, integer image bounds, clone expansion/differentiation and antibody release; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasInsulinStoryView` — five source stages, distinct potassium/calcium gate timings, vesicle approach/fusion/aperture/release thresholds, membrane pore and channel exclusion clip, original blood route and dedicated islet vector (18 paths / 16 gradients); source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasHomeostasisStoryView` — separate glucagon-response and sweat-cooling courses, source glycogen/relative-liquid rules, five exact routes including eleven-segment eccrine duct, reverse transport/salt recovery, dry/humid evaporation and dedicated alpha/sweat artwork (12 paths / 7 gradients); source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSignalStoryView` — separate synaptic/myelin/thyroid-feedback courses, six exact routes, cached length-aware 27-unit trails, staged vesicle release, glial wrapping/node/relative-travel scenes, thyroid conversion and inhibition, original neuron and two dedicated vector plates (34 paths); source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasBarrierStoryView` — five source stages, basal division, ascent/flattening and shedding, granular lipid secretion, intact/disrupted water escape rates, source Illustrated primitives and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasGameteStoryView` — separate sperm/ovum transport courses, five exact tracks, source formation/epididymal maturation/storage, moving duct constriction, follicle opening/release/pickup, fimbriae/cilia/ampulla scenes and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasChemicalSenseStoryView` — separate olfaction/taste courses, source airway/nerve/three receptor paths, non-looping delayed transfer, mirrored receptor layer, odor channel combinations, taste pore/ATP/nerve stages and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasMotionSenseStoryView` — separate touch/vestibular courses, four exact routes, source pressure/release/PIEZO2/spike rules, labyrinth/fluid/cupula/otolith scenes, head-gaze counter rotation and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasOcularStoryView` — three five-stage courses, directional retinoid transfer/RPE65 conversion, rod-bipolar/AII ON-OFF relay, limbal migration, corneal stratification/shedding and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasAirwayStoryView` — five source stages, exact lung/airway outlines and two tracks, particle settling, goblet secretion, phased ciliary waves, clipped mucus transport and swallowing handoff; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasEndothelialStoryView` — five source stages, five exact outlines, three lymph routes, separate water filtration/opposing solute diffusion/protein retention/lymph collection, gradients and bounded bilingual legend; source/grammar checks only, native pixels unverified.
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

Player checkpoint: dedicated source tables contain 3127 exact strings in each language; registry exposes thirty-one courses through nineteen of 81 renderer classes. Paired or grouped courses retain dedicated source renderers, including the three signal and three ocular courses. These source implementations have not run on a device. Generic chapter controls, lifecycle pause, references and separate live/persisted state are connected; no unsupported course is replaced by a generic picture. The enabled-course audit also checks every enabled ID against the pinned 101-course catalogue.

Signal trail lengths are cached once per source route. The small geometry helper uses subdivided chord/control-polygon bounds with a shared error budget ([Gravesen, 1997](https://orbit.dtu.dk/en/publications/adaptive-subdivision-and-the-length-and-energy-of-b%C3%A9zier-curves/)); rendering still trims the native Path. Added, unexecuted XCTest source compares straight/quadratic/cubic cases to analytic lengths. This does not prove native Path trimming accuracy, arc orientation, compilation or pixels.

Heartbeat uses the original byte-identical heart PNG and 625 mesh vertices / 1152 triangles. Triangle ordering follows the Android bitmap-mesh implementation in [AOSP SkiaCanvas](https://android.googlesource.com/platform/frameworks/base/+/d18c61ae8e7ec024352e71e405a040b829376f50/libs/hwui/SkiaCanvas.cpp). The Metal shader is registered in Sources for the bundle default library ([Apple Metal libraries](https://developer.apple.com/documentation/metal/metal-libraries)); textures explicitly use premultiplied RGBA and top-left coordinates. If Metal initialization fails, the same indexed triangles use clipped CoreGraphics affine transforms. Shader compilation, alpha/orientation correctness and rendered pixels still require native verification.

The player does not serialize the entire atlas each frame. A non-published live phase cache supplies current question snapshots; pause/reset/exit commit the bound course phase. Dedicated Function decoding tolerates corrupt Function-only state without discarding other selection fields. New XCTest source covers timing, snapshots, restoration and uptake checkpoints; it has not been executed.

Kotlin evaluation is catalogue-data extraction with resource/constant stubs, not an Android build, renderer fixture or test run.
Windows has no Xcode. Do not claim Swift type checking, native compilation, device/simulator, VoiceOver or pixel acceptance.
No XCTest execution or IPA generation is requested.
