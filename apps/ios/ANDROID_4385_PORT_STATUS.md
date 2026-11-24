# Android #4385 iOS Port Status

Source implementation and runtime wiring are present. This is not native parity
acceptance, a compiled iOS release or a device-verified build.

## Source And Dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4385
- Source merge: `a81aa85a1c81e41ff19a032eabea1eddcd2371dc`
- Inventory: `ANDROID_4385_SOURCE_INVENTORY.json`, 93 pinned files.
- Branch starts at `ba009094137225e74b16cebbb7d434ccd74fd24d` from iOS #4491.
- #4491 was open when this branch was created. Before publishing a formal
  `main`-based PR, recheck its merge status and the actual main-to-head diff.
- No #4385 PR has been published. Do not publish partial renderer coverage.

## Implemented In This Branch

- Separate `AtlasRegional.strings`: 431 changed/added resources per language,
  English and Simplified Chinese, with identical keys and no inherited translations.
- Latest table takes precedence over older atlas resources without rewriting the
  frozen #4384 source resources.
- Calf-pump teaching model for soleus and gastrocnemius: original ranges/defaults,
  rate axis, net-stroke formula, result/companion, references, accessibility and
  controls-before-chart placement through the existing material-response panel.
- Chamber, valves, forward-flow and returning-flow diagram; reversed horizontal
  arrowheads preserve the original positive-direction diagrams.
- Ligament-guidance first chapter now crossfades ACL/PCL footprint focus.
- Regional catalogue snapshot evaluated from original Kotlin declarations:
  114 courses, 544 chapters, 261 references and 289 owner routes. The runtime now
  selects this pinned revision by default; the #4384 snapshot remains available
  only through an explicit archived revision read.
- Dedicated ankle-mortise renderer: five scenes, nine source paths/80 commands,
  smooth easing, talar rotation and exaggerated syndesmosis displacement.
- Dedicated scrotal-heat renderer: three scenes, eleven source paths/58 commands,
  mirrored compartments, open superior tunica attachment, vessel gradients,
  counter-directed arc-length tracers and separate heat-transfer arrows.
- Dedicated penile-urinary renderer: three scenes, ten source paths/63 commands,
  mirrored transverse tissue, continuous longitudinal centerline and independent
  proximal/distal arc-length tracer intervals, with a transparent-border overlay.
- Dedicated skull-protection renderer: four scenes, sixteen original SVG paths/213
  commands, progressive sutures, dashed layer locator, diploe clipping and fluid
  tracers clipped outside the brain and inside the subarachnoid-space schematic.
- Dedicated vertebral-motion renderer: three scenes, eleven original SVG paths/69
  commands, rigid upper-vertebra transform, stationary lower vertebra, attached disc
  edges, clipped nucleus/lamellae and transformed landmark callouts.
- Dedicated clitoral-sensory renderer: four scenes with nine source paths/46
  commands, sequential anatomical focus, mirrored dorsal nerve context and
  direction-preserving afferent tracers through endings, dorsal and sacral routes.
- Dedicated vestibular-gland renderer: four scenes with seven source paths/26
  commands, radial secretory cells with an open duct neck, three acinar branches,
  length-weighted shared-duct transport and independent paired outlet tracers.
- Dedicated tenocyte-tendon-matrix renderer: four stages with original parameterized
  fiber/cell curves, clipped matrix, fiber-vertex tracking marks, independent
  secondary cells and dashed resting-profile comparison. Poses are unitless art,
  not measurements of tissue/cell strain.
- Dedicated accessory-gland routing renderer: five scenes, six original bilateral
  duct routes, source stage colors, eighteen stage-specific callouts with original
  copy overrides and independently delayed prostate branches.
- Dedicated vulvar-protection renderer: five scenes, ten original contours/50
  commands, nine emphasis tracks, ten source feature anchors, paired traces and
  fixed asymmetric comparison profiles. Only reading emphasis moves.
- Dedicated pectoral-action renderer: five scenes, five original outlines,
  parameterized clavicular/sternocostal fans, humeral insertion, overhead rotation,
  progressive/return sweep arcs and chapter-specific attachment callouts.
- Dedicated latissimus-action renderer: five scenes, six original outlines,
  source sagittal-then-frontal projection, projected arm/attachment, parameterized
  muscle sheet, dashed hidden tendon, twenty-segment guides and return directions.
- Dedicated uterocervical renderer: three scenes with a fixed locator and enlarged
  regional sections. Original pure Kotlin declarations produce 29 static paths/216
  commands, including loop textures, relative quadratics and four continuous trace
  DTOs. Native moving folds retain original controls and fixed canal/opening edges.
- All thirteen new renderers have Xcode source registration and explicit dispatch
  in the active 114-course registry. Catalogue and renderer coverage are enabled
  together, preserving all 101 baseline registrations.
- All 23 new/modified VectorDrawable resources imported into separate regional PDF
  assets: 298 source paths and 68 native gradients. They do not overwrite frozen
  #4384 PDFs. Regional selectors/features now reference the revised assets.
- All 73 current structure views now use regional PDF copies, including 51
  previously unchanged source vectors: 1,015 paths and 171 gradients. This removes
  inherited non-equivalent quadratic encodings from the active structure views.
  Erector, ligament, pineal and placental course drawing also use these corrected
  copies; the old PDFs remain only for frozen snapshot checks/fallback data.
- Regional conversion preserves scoped clipping paths and converts SVG Q/T curves
  into mathematically equivalent cubic PDF paths, retaining relative commands and
  reflected quadratic controls. Pinned MIT-licensed svgpath 2.6.0 resolves shorthand
  controls before PDF encoding, including the skull's consecutive-T chain. Vendor
  provenance/license and official registry archive-integrity evidence are retained.
- Omitted gradient axis coordinates now use Android's zero defaults, verified in
  [Android GradientColor source](https://android.googlesource.com/platform/frameworks/base/+/4e4cac3031513a2a739d3c55e9e6abf738b88eec/core/java/android/content/res/GradientColor.java).
- Regional structure metadata extracted from the original pure Kotlin declarations:
  73 unique views for 72 owners, 252 annotations and 36 links. This preserves the
  two independent tenocyte views, the taste-pore coordinate correction, new view
  keys/selectors and revised microglia/ependymal/rib artwork references. The snapshot
  is loaded and validated by the runtime; all 73 views point to regional PDFs.

## Runtime Integration

- Default #4385 revision validates all course/chapter/reference/route counts and
  source commit. The reader rejects a mismatched requested revision.
- Every current course has explicit native dispatch; all 289 owner routes and
  124 related destinations are present in the evaluated catalogue.
- Regional structure views take precedence over frozen detail plates without
  removing musculoskeletal context views. Tenocyte gets two distinct selectors,
  with the original cellular context first and tendon-longitudinal view second.
- Reference guards include the four added source hosts. Structure source URLs
  remain restricted to the exact previous and regional source sets.
- Pineal retains the existing preserved-vector PDF/Image drawing path rather than
  importing Android's VectorDrawable-specific bitmap cache workaround. Device
  zoom/rewind behavior has not been accepted or measured.
- Archived checks explicitly audit frozen cohorts; current runtime has its own
  114-course/73-view integration audit. XCTest source expectations were updated,
  but XCTest has not been executed.

## Publication Status

- Serial source-contract verification passed for all 93 original changed files.
  `ANDROID_4385_PORT_COVERAGE.json` records every hash, disposition, iOS target,
  source check and platform-specific verification limitation.
- Latest fetched main is `bcc2d4c0fc9526d2b047741a3d47f3cece3d9c2b`; it is an
  ancestor of this branch. #4491 remains open and its foundation is still included
  in the main-to-head diff. A `main` base does not make this branch independent.
- Published formal non-draft PR #4492 for Android #4385:
  https://github.com/galaxyssi/GalaxySSI/pull/4492
  Verified base `main`, state `OPEN`, `isDraft: false`, and `MERGEABLE` at code
  commit `d8427c760cfcf714dfc2332b0cad9cee895c7aae`. `UNSTABLE` check status is
  not a native/device acceptance claim. No IPA was generated.

## Verification Boundary

Source-only checks passed for the calf-pump source/formula/axis/diagram, 81,406
analytic integer-grid combinations, ankle paths/scene contracts, scrotal paths and
tracer controls, penile paths and proximal/distal tracer controls, bilingual delta
regeneration, preserved #4384 catalogue extraction
and material-response contracts. Swift grammar parsing passed on the edited files
in both preprocessor branches. Project structure and eight module-setting subset
checks passed. These checks do not compile or run Swift or Android scenes.

No XCTest, Xcode build, IPA, simulator/device execution, VoiceOver acceptance or
pixel verification has been performed. Windows cannot supply native iOS acceptance.

Axial source audit additionally passed for the 27 exact path declarations, SVG
relative/reflected control fixtures, twelve skull callouts and 363 analytic
vertebral poses. Regional PDF checks passed for all 23 resources, scope-preserving
clipping, strict rejection of unsupported transformed clips and 363 sampled points
of quadratic/cubic equivalence. The retained #4384 ligament PDF check still passes.

Regional structure metadata checks passed for all 73 views: graph identities,
annotation/link coordinates, both language tables, unique view keys, PDF resource
availability, revised artwork aliases and the two-view tenocyte snapshot. This
does not prove executed runtime routing or selection behavior. Separate source
integration checks now cover the active runtime branches, not native execution.

Historical #4384 PDFs remain unchanged. Their retained-batch checks compare
encoded operations and do not prove SVG Q/T semantic equivalence. Active regional
structure views and the four PDF-backed structure course scenes use corrected
copies instead. Other unchanged #4384 PDF course cohorts still need a separate
quadratic audit; passing their old encoded-operation checks is not proof that this
broader inherited issue is resolved.

The completed source run verifies the corrected 73-view PDF cohort against 1,015
source paths and 171 gradients, plus all 23 changed source vector assets. The
consecutive-T fixture reproduces the skull source chain with independent expected
controls, and the vendored parser archive matches official npm SHA-512 metadata.

Clitoral/vestibular source checks passed for all 16 paths/72 commands, nine
continuous trace control sets, nineteen bilingual labels and nineteen source
callouts. Tenocyte checks passed for parameterized fiber/cell curve controls,
deformation stage continuity, tracking-mark vertices, the resting profile and 484
analytic poses. These are source checks, not execution of the native renderers.

Accessory-gland source checks passed for all six bilateral route controls, route
colors, eighteen evaluated Callout/copy declarations, five stage mappings and 242
analytic delayed-progress samples. Vulvar source checks passed for ten contours/50
commands, nine trace control sets, ten feature anchors matching Kotlin-extracted
metadata, eight callouts and 968 analytic reveal samples. No native acceptance.

Shoulder source checks passed for eleven outlines/84 commands, all original
parameterized fan/sheet/back curve controls, eleven bilingual labels, five-stage
models and 605 analytic pose/continuity samples. Uterocervical checks re-evaluated
29 original static paths/216 commands and verified moving-lining controls, nine
callouts, fixed locator/openings and 121 analytic emphasis/fold samples. These
checks do not execute Swift, Canvas, device rendering or native compilation.
