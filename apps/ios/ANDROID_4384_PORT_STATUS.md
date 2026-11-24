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
- [ ] Complete Function-tab player integration across all source courses. Core player, course selector, controls, source links, phase restoration and lifecycle are wired for sixty-six courses through fifty-four dedicated renderers; other courses still await their dedicated renderers.
- [x] Connect optional persisted Function selections without changing quantitative simulation selections. Keep live animation phase outside published/serialized state; pause/exit commits it, while question snapshots read current live phase. Corrupt Function-only storage does not discard unrelated selections.
- [ ] Import all new/revised illustration resources and cutaway geometry.
- [ ] Port additional structure views, canonical/feature routing and related Function destination navigation.
- [ ] Port ventilation, diffusion and skeletal model changes and their parameter/result UI.
- [ ] Update Agent public context and fallback question paths with the active Function lesson/chapter.
- [ ] Complete every renderer below, preserving chapter-specific geometry and motion rather than generic stand-ins.
- [ ] Static source/resource/grammar/project checks across the completed scope, then review and publish one formal main-based PR.
- [ ] Synchronize any newly merged predecessor PRs and update dependency scope before publication.

## Renderer Parity
Next renderer: port HealthAtlasAutonomicRelayStoryView, then continue the source-order list. Sixty-six courses are enabled through fifty-four dedicated renderers; do not broaden FunctionRendering before the corresponding native renderer is implemented.

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
- [x] `HealthAtlasPlateletStoryView` — five source stages, exact gap-wall geometry, five arrivals, fourteen-point activation morph, delayed recruitment/signal spread/fade, five progressively trimmed fibrin tracks and bounded bilingual annotations; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCartilageStoryView` — five source stages, smoothed local indentation with fixed bone attachment, patellar travel/load, clipped matrix/fluid, two shoulder-flow paths with return/fade and bounded bilingual annotations; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSmoothMuscleStoryView` — five source stages, continuous chapter endpoints, four shared-contour open-ended layers, ahead dilation/behind constriction, bolus scaling, fiber highlights and bounded bilingual callouts; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasTendonStoryView` — five continuous load stages, exact bone/cortical outlines and fixed insertion, muscle/tendon deformation, three uncrimping collagen rows, sequential focus/force arrows and bounded bilingual callouts; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSurfactantStoryView` — five source stages, exact sac/four-curve film route, stored-packet highlight, liquid-connected release pore, asymmetric film spreading, breath scaling and bounded bilingual annotations; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasIntestinalAbsorptionStoryView` — five source stages, exact six-curve villus, six cargo-specific tracks and three anatomical outlines, cached normal-based brush/cell geometry, clipped inset highlights, separate blood/lymph transport and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasKneeStoryView` — five source stages, six shared poses, three exact bone outlines, shin rotation/moving attachments, quadriceps/hamstring deformation, route-specific pulses/arrows and bounded bilingual annotations; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCardiacSignalStoryView` — five source stages, five conduction tracks and three heart outlines, sequential trunk/branch timing, node pulses, cell shortening/recovery, calcium/filament scenes and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasRedCellStoryView` — five source scenes, exact alveolar outline, bound/free oxygen, delayed lung loading, flowing rich/muted cells, continuous plasma-to-tissue handoff and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSalivaStoryView` — five source stages, six exact outlines and four tracks, five-angle acinar cutaway, fluid/protein release, directional sodium/potassium exchange, mouth flow and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasVenousReturnStoryView` — five source stages, four exact calf outlines, timed proximal/distal valves, compressed sinus/waist geometry with clipped leaflets, pump ejection/refill, source flow/focus alpha and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasHairCycleStoryView` — five source stages, fixed upper follicle and exact lower-follicle curves, matrix regression/rest, pore-following old-hair lift/fade, delayed replacement and bounded bilingual callouts; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasUrineRouteStoryView` — five source stages, seven tracks/four exact outlines, 65-sample deforming channels, peristaltic pinch/tunnel gating, reservoir/outlet timing, clipped pulse intervals, mirrored lower inlets and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasPleuraStoryView` — five source stages, exact airway/costal/basal curves, shared layered contour, mirrored heart-side notch/fissures, diaphragm coupling, sheet-attached sliding marks and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCalciumFeedbackStoryView` — five source stages, ten exact tracks/four outlines, calcium/PTH feedback strength, distinct calcium/PTH/vitamin-D markers, renal retention/activation, intestinal uptake and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasMammaryStoryView` — five source stages, open arc-to-duct outline, butt-cap gradient wall/transparent milk tint, luminal/basal cells, stored milk, delayed oxytocin/squeeze, finite outflow and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCerebellumStoryView` — five source stages, seven exact outlines, source repeat/deviation timing, fixed-length two-link arm, predicted/actual traces, error comparison, delayed feedback and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasMelaninStoryView` — five source stages, exact cell/wafer geometry and point sets, three branches/transfer tracks/five cap tracks, envelope-to-core handoff, qualitative UV cues and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasLarynxStoryView` — five source stages, five exact outlines, shared superior/frontal fold gap, breathing/adduction/vibration/recovery timing, gated airflow, acoustic-front cues and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasAstrocyteStoryView` — five source stages, four exact outlines/fifteen routes, delayed glutamate release/uptake, glutamine conversion/return, local potassium buffering, clipped capillary flow and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSplenicFilterStoryView` — five source stages, exact spleen/deforming macrophage outlines, three tracks, 64-point wall-relative red-cell deformation, retention/capture/recycling timing, clipped tissue and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasThymusStoryView` — five source stages, seven exact anatomy outlines/three travel routes, mirrored locator, clipped cortical/medullary densities, positive/negative selection timing, integer-alpha cell layers, dashed travel and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasBrainstemRhythmStoryView` — five source stages, six exact outlines/five routes, dynamic lung/diaphragm curves, clipped fissures, network topology, sequential motor branching/trails, respiratory gating and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasFibroblastStoryView` — five source stages, eight exact outlines, eleven scaffold/four paired outgoing/two turnover fibers, control-point interpolation, repair cues, integer-alpha double strokes, source-length trim ordering and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasArterialStoryView` — five source stages, exact arch/three branch routes, four 25-sample layers, independent wave/flow formulas, coupled cross-section, open cutaway edges and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasChondrocyteStoryView` — five source stages, exact patch/reticulum/profile geometry, nineteen fibrils/four collagen/three deposit routes, hydration and compression mapping, synchronized label anchors, distinct molecular/water markers and bounded bilingual labels; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasAdrenalMedullaStoryView` — five source stages, five exact outlines/eight routes, dynamic vesicle pocket, neural/release/circulation windows, integer-alpha cargo/blood cells, residual background, exact label anchors and bounded bilingual resources; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasGastricAcidStoryView` — five source stages, eight exact outlines/two routes, separate recruitment/exchange/chloride/lumen windows, open canaliculus, distinct ion markers, nonzero feedback floor, exact callout anchors and bounded bilingual resources; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasMarrowStoryView` — five source stages, exact bone/stroma/nuclear/shared-membrane paths, twenty-eight tissue positions/two lineage routes, sampled sinusoid, distinct cell phenotypes, maturation and delayed crossing/flow windows, exact bilingual anchors; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCoronaryStoryView` — five source stages, thirteen exact outlines/seventeen tracks, cached length-bounded arrows, integrated left-flow timing, compressed capillaries, negative-time return wrap, oxygen cues, exact stream signatures/label positions and bilingual resources; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasPodocyteStoryView` — five source stages, exact contours/glyphs/routes, sampled layers and fenestral gaps, transparent gradient endpoints, separate blood/filtrate particles, source timing/references and bilingual anchors; separate legacy four-stage structure entry retained; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasEndometriumStoryView` — five source stages, exact uterus/guide/gland/fragment paths, surface erosion and stromal/secretion windows, retained basal tissue, positive/complement tissue clipping, repair openings and stage-specific bilingual anchors; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCranialReflexStoryView` — five source stages, nine exact outlines/seven mirrored tracks, crossed afferent/relay endpoints, finite light/neural signal windows, bilateral pupil narrowing, forty iris spokes, integer-alpha node/retinal cues and eleven bilingual anchors; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasSebaceousStoryView` — five source stages, nine exact outlines/two particle tracks, thirty-four cell/lipid positions, clipped skin locator, source arc/oval focus cues, cell replacement/maturation/holocrine fade, distinct canal/duct transport and bilingual anchors; source/grammar checks only, native pixels unverified.
- [x] `HealthAtlasCerebralSensorimotorStoryView` — five source stages, seventeen exact outlines/five cached and one dynamic information track, nine timing windows, continuous two-stage reaching with fixed arm lengths, dashed direction arrows, gated pulse/cue rings and eleven bilingual anchors; source/formula/grammar checks only, native pixels unverified.
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

Player checkpoint: dedicated source tables contain 3127 exact strings in each language; registry exposes sixty-six courses through fifty-four of 81 renderer classes. Paired or grouped courses retain dedicated source renderers, including the three signal and three ocular courses. These source implementations have not run on a device. Generic chapter controls, lifecycle pause, references and separate live/persisted state are connected; no unsupported course is replaced by a generic picture. The enabled-course audit also checks every enabled ID against the pinned 101-course catalogue.

Signal trail lengths are cached once per source route. The small geometry helper uses subdivided chord/control-polygon bounds with a shared error budget ([Gravesen, 1997](https://orbit.dtu.dk/en/publications/adaptive-subdivision-and-the-length-and-energy-of-b%C3%A9zier-curves/)); rendering still trims the native Path. Added, unexecuted XCTest source compares straight/quadratic/cubic cases to analytic lengths. This does not prove native Path trimming accuracy, arc orientation, compilation or pixels.

Heartbeat uses the original byte-identical heart PNG and 625 mesh vertices / 1152 triangles. Triangle ordering follows the Android bitmap-mesh implementation in [AOSP SkiaCanvas](https://android.googlesource.com/platform/frameworks/base/+/d18c61ae8e7ec024352e71e405a040b829376f50/libs/hwui/SkiaCanvas.cpp). The Metal shader is registered in Sources for the bundle default library ([Apple Metal libraries](https://developer.apple.com/documentation/metal/metal-libraries)); textures explicitly use premultiplied RGBA and top-left coordinates. If Metal initialization fails, the same indexed triangles use clipped CoreGraphics affine transforms. Shader compilation, alpha/orientation correctness and rendered pixels still require native verification.

The player does not serialize the entire atlas each frame. A non-published live phase cache supplies current question snapshots; pause/reset/exit commit the bound course phase. Dedicated Function decoding tolerates corrupt Function-only state without discarding other selection fields. New XCTest source covers timing, snapshots, restoration and uptake checkpoints; it has not been executed.

Kotlin evaluation is catalogue-data extraction with resource/constant stubs, not an Android build, renderer fixture or test run.
Windows has no Xcode. Do not claim Swift type checking, native compilation, device/simulator, VoiceOver or pixel acceptance.
No XCTest execution or IPA generation is requested.
