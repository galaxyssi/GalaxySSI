# Android Body Atlas

The public teaching catalogue contains 14 navigation categories, 167 canonical
organ/structure entries, 105 cell types or subtypes, and one platelet-fragment
entry. Shared structures have one stable identity and multiple category links.
The taxonomy is a navigation aid, not an exhaustive ontology of all human cells.

`HealthBodyAtlas` validates the bundled graph and resolves English or Chinese
resources. Search never reads personal health databases. Every entry has a
specific function description and a linked four-stage teaching mechanism.

`HealthAtlasMeasurements` uses the existing indexed trend repository and privacy
audit scopes. Decrypted chart state is discarded on backgrounding; cancellation
and generation tokens prevent stale results from returning to a different
selection. Agent analysis of measurements uses the existing disclosure flow.
Knowledge-only Agent requests use a single-use in-process handoff token and a
separate conversation, with no attached health observations.

Cardiac output, ventilation, renal solute balance, potassium equilibrium
potential and oxygen binding are fixed-input teaching equations. Other sequences are qualitative,
not validated quantitative patient models.
No organ score, biological age, drug dose or treatment outcome is inferred.

## Interactive Physiology

`HealthAtlasPhysiology` provides four independently bounded teaching models:

- Alveolar ventilation subtracts dead-space volume from tidal volume before
  multiplying by respiratory rate. Total minute ventilation remains visible
  separately. The equation follows the volume definitions; it does not calculate
  oxygen saturation, carbon dioxide or a ventilator setting.
- Renal solute excretion uses filtered load minus reabsorbed load plus net
  secretion, in mg/min. Reabsorption is a percentage of the filtered load.
  This is a whole-nephron conservation example for an unspecified freely filtered
  solute, not urine volume, an eGFR estimate, or a drug-specific clearance model.
- Potassium equilibrium potential uses the Nernst equation with natural log,
  Kelvin temperature (310.15 K), charge +1 and an explicit volts-to-millivolts
  conversion. It assumes a potassium-only membrane and concentrations as
  activities. It is not a measured resting potential or an action potential.
- Oxygen binding separates hemoglobin saturation from bound and dissolved oxygen
  content. Its assumptions and references are detailed below.

Twenty-two canonical entries expose these associated processes. Tubular cells
do not claim to perform the entire nephron model, nor does a brain illustration
claim to measure an individual neuron. Unrelated entries do not inherit them.
Slider ranges are teaching controls, not clinical reference intervals.

Native parameter-response curves hold other inputs fixed and mark the selected
input. They have numerical accessibility descriptions, not only colored pixels.
Inputs update locally, restore per entry across recreation, and reset explicitly;
invalid saved arrays are ignored. Model values never enter the health database.
The knowledge-only Agent confirmation includes the current inputs, output,
assumptions and source both from Simulation and from Research / Physiology.
Existing separate consent for personal measurements is unchanged.

Model references:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption
- https://neurotext.library.stonybrook.edu/C2/C2_4/C2_4.html

## Mechanisms and Research

The eleven macroscopic circulation entries use a native double-circulation
diagram with the existing lung, heart and whole-body illustrations. Directional
paths follow tissues, right heart, lungs, left heart and tissues; pulmonary
arteries are relatively oxygen-poor and pulmonary veins relatively oxygen-rich.
Both color and localized stage text identify each route. The anatomical heart
image represents one heart; side labels describe the simplified right/left flow
ports, not exposed chambers on the external image.

Stage selection, seeking and playback use the same saved phase as the rest of
the simulator. Teaching cardiac output updates the heart label on the heart and
cardiovascular-system entries only. Other associated entries do not inherit an
invented numerical flow. Animation time is illustrative, not measured transit
time or hemodynamics. Gas exchange, pressure, coronary branches and shunts are
not computed. Inputs do not read or write personal health records.

Native lung and heart targets open their canonical structure pages and retain
the originating research topic, phase and cardiac inputs on return. Public
Agent previews include the selected stage, circuit scope, full flow sequence
and reference only for the active physiology topic. Other research topics and
unrelated anatomy do not inherit this context.

Circulation reference:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy

Each entry opens a native three-tab research surface. Physiology retains the
entry's teaching sequence and controls. Drug pathways show a clearly labeled
whole-body ADME overview with links to relevant structures, plus a normalized
single-compartment first-order elimination explorer. The latter starts at 100%
and has no drug identity, dosage, patient data or therapeutic thresholds.
Its half-life and elapsed-time controls restore independently for each entry.
Drilling into a structure and returning restores the research tab and inputs.

The aging tab summarizes research themes and their evidence limits, links the
2023 Cell review and related anatomy source, and offers an Agent handoff carrying
the selected entry, research topic, sources and public teaching assumptions.
None of these tabs reads personal health data or infers an aging score.
Process labels use measured multiline layout, including larger font settings.

Research references:
- https://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics
- https://pharmacologyeducation.org/clinical-pharmacokinetics/
- https://pubmed.ncbi.nlm.nih.gov/36599349/

## Design Coverage and Remaining Work

The pinned Agent action follows the current surface. Public catalogue, mechanism
and research prompts use `HealthAtlasAgentContext`: selected anatomy, current
teaching stage, cardiac or other quantitative inputs, assumptions and sources.
Animation pauses before the confirmation preview so the preview is a stable
snapshot. Inactive research models are not added to another topic's prompt.

On personal values, the pinned action opens the existing scoped trend analysis
and consent flow, retaining metric, units, time range and data revision. It is
disabled while loading, for empty charts and after backgrounding or access
revocation. It never falls back to a public anatomy question. Selecting a new
metric or period invalidates the previous handoff before starting the next read.
The existing local preview, provider choice and disclosure checks remain intact;
entering this screen alone does not authorize a network request.

`HealthAtlasAgentLiveTest` is an opt-in real-provider check using public synthetic
cardiac inputs and one follow-up. It creates its own conversation, never reads
personal measurements and does not delete messages. Its report stays local.

The native catalogue and research surface are not the complete virtual-human
model shown in the supplied design references. Completion requires more than
having a working generic panel for every catalogue entry:

- Extend the twenty anatomical illustrations and selectable structures to the
  remaining systems, organs and cells. Each image must depict its named entity;
  related anatomy must not be presented as an isolated structure it does not show.
- Add entity-specific mechanism diagrams and model inputs where supported by
  a documented scientific model. A shared process is explicitly associated
  context, not evidence that each listed cell performs all of its stages.
- Expand research pathways, including multi-organ distribution and clearance,
  beyond the introductory normalized elimination model. Full PBPK or aging
  predictions require sourced parameters, model validation and explicit scope;
  arbitrary organ scores must not stand in for those models.
- Verify real Agent handoffs for public explanations and separately consented
  personal measurements, preserving the selected entity, sources and conversation.
- Verify navigation, zoom, fullscreen, accessibility, large type and both themes
  across phones and tablets. A passing narrow device suite is not proof that the
  entire anatomical catalogue has the required artwork or model coverage.

Personal health observations, public anatomy and synthetic model outputs remain
separate domains throughout. Existing Agent page layout and health records are
not modified by atlas navigation or teaching parameter changes.

## Oxygen Binding Teaching Model

The blood and erythrocyte entries expose the same bounded equilibrium model,
with independently restored inputs per entry. PO2 (0-150 mmHg), P50 (15-40 mmHg)
and hemoglobin (50-200 g/L) are synthetic teaching controls, not reference ranges.
The response chart plots saturation against PO2 while holding other inputs fixed.
Changing hemoglobin changes oxygen content, not the saturation curve.

The Hill fraction is `S = 1 / (1 + (P50 / PO2)^2.7)`, with `S = 0` at zero PO2.
The default P50 is 26.8 mmHg. This uses only the introductory Hill equation in
Dash and Bassingthwaighte (2010), not their full multivariable model. Its reported
useful fit is approximately 20-98% saturation; extremes are illustrative.
Bound oxygen is `1.34 * (Hb_gL / 10) * S`; dissolved oxygen is `0.0031 * PO2`.
Both and their sum are shown in mL O2/dL whole blood. The constants and content
balance are described in Driver et al. (2012); the BOLD model is not implemented.

- https://pmc.ncbi.nlm.nih.gov/articles/PMC2862600/ (Eq. 1)
- https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/ (oxygen-content balance)

Acid-base state, CO2, temperature and abnormal hemoglobins are not independent
inputs. No oxygen-delivery, pulse-ox, treatment or patient prediction is made.
The panel does not read or write personal health records. Agent previews include
the current inputs, separate components, limitations and both source links only
for the selected physiology topic; other anatomy and research topics exclude it.
The qualitative cell animation remains separate from the equilibrium calculation.

## Sources and Artwork

- OpenStax, *Anatomy and Physiology 2e*: chapter links are stored with each mechanism.
- https://openstax.org/books/anatomy-and-physiology-2e/pages/19-4-cardiac-physiology
- https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing
- https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas
- https://www.humancellatlas.org/
- https://www.proteinatlas.org/humanproteome/single+cell/single+cell+type

The whole-body mannequin, external heart and beta-cell cutaway PNGs were
generated using the built-in image-generation tool. They are teaching
illustrations, not scans, diagnostic images or verified anatomical meshes.
Generation specifications: a neutral anterior anatomical mannequin with visible
thoracic/abdominal organs; an anterior external heart; a beta-cell cutaway with
nucleus, rough ER, Golgi, mitochondria and secretory granules. All were requested
without baked-in labels so navigation labels remain native and localizable.

Four additional generated plates show a left lateral brain, anterior lungs and
trachea, liver with its associated gallbladder, and a single kidney in coronal
section. They use transparent backgrounds without baked-in labels. Generation
specified cerebral/cerebellar/brainstem regions, right/left lung lobe asymmetry,
the gallbladder below the liver, and cortex/medulla/pelvis/ureter respectively.
`HealthAtlasPlates` binds each image and native marker to canonical entries.
Shared plates explicitly identify their context and view; selecting an already
selected marker does not add navigation history. An external heart is not used
as an illustration of internal valves. Labels are measured and packed in visual
order instead of overlapping at the lower image edge.

Anatomy references for these plates and kidney structure descriptions:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/13-2-the-central-nervous-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/22-2-the-lungs
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-3-gross-anatomy-of-the-kidney

These generated illustrations remain schematic and are not validated medical
meshes. Marker and pixel tests check rendering/navigation, not clinical accuracy.

Specialized artwork for the rest of the catalogue and quantitative research
models are separate work. An unrelated illustration must not be relabeled as a
different organ or cell.

## System and Accessory-organ Plates

Three additional generated transparent PNGs show urinary organs, the digestive
tract from esophagus to rectum, and the pancreas with its adjacent duodenum.
They follow the existing bitmap style and native, localized clickable labels.
The urinary overview links to the separate kidney section; selecting ureters
from that section opens their larger urinary context. Back and saved selection
retain each preceding anatomical view. Shared views explicitly name their owner.

The urinary outlet is a simplified schematic, not a male/female urethral length
comparison. The digestive plate omits accessory glands. The pancreas plate
exposes the main duct, not microscopic islets or acinar cells. Those microscopic
entries must not inherit this macroscopic artwork. Native source rows identify
anatomy references, and public Agent previews retain the selected plate context
and schematic-artwork disclaimer without attaching personal measurements.

Built-in image-generation prompt set:
- Anterior urinary organs only: two inward-facing kidneys, two independent
  ureters, one bladder and a short schematic urethral outlet; no torso, adrenal
  glands, text, leader lines or background.
- Anterior esophagus-to-rectum tract: stomach on the viewer's right, central
  small bowel, an outer haustrated colon, appendix on the viewer's lower left;
  accessory organs omitted; no labels or arrows.
- Pancreas and C-shaped duodenum: head on the viewer's left, tapered tail to the
  right, main duct visible within a cutaway and draining toward the duodenum;
  no bile duct, vessels or enlarged microscopic islets; no labels or arrows.

Final project assets are `res/drawable-nodpi/health_atlas_urinary.png`,
`health_atlas_gut.png` and `health_atlas_pancreas.png` in the Android app.
These generated plates are teaching schematics, not medically validated meshes.
Pixel and marker tests verify rendering and navigation, not clinical accuracy.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport
- https://openstax.org/books/anatomy-and-physiology-2e/pages/23-1-overview-of-the-digestive-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder

## Cell-specific Processes

The thirty core cells now have their own four-stage teaching processes and
chapter references in the catalogue, rather than reusing a system-level cycle.
These include the ten blood/immune examples, three neural examples, three
muscle types, four skin/connective/metabolic examples, four bone/cartilage
examples, endothelium, hepatocytes, beta cells, enterocytes and two gametes.
The loader rejects a cell-specific mechanism assigned to a different entity.
Seven additional renal/urothelial cell types have dedicated processes, bringing
the total to 37; five respiratory-related cells extend that to 42. Other cell
subtypes still use broader pathways until dedicated content is reviewed; this
is not a claim of complete single-cell biology coverage.

Each stage is a native focusable button. Selecting a stage pauses playback,
updates the progress position and preserves the other simulation inputs.
Text height is measured before layout, including at large font sizes.
The processes are qualitative teaching sequences, not biological clocks,
diagnostic predictions or calculated cell health scores. An example is scoped
in its title when it describes only a subtype or one function.

Two additional bitmap plates depict a mature biconcave erythrocyte without a
nucleus and a representative myelinated multipolar neuron. They were generated
with the built-in image tool. The specifications requested one isolated cell,
transparent alpha, no baked-in labels and no cropped tips. The neuron edit
requested removal of surrounding glow and at least eight percent free margins,
while preserving one axon, separated myelin segments and terminal branches.
They are bound only to the matching catalogue entries, not to other glia or
white blood cells. These remain schematic illustrations, not microscopy.

Cell process references are the per-entry OpenStax links. Key chapters include:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/18-3-erythrocytes
- https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets
- https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue
- https://openstax.org/books/anatomy-and-physiology-2e/pages/12-5-communication-between-neurons
- https://openstax.org/books/anatomy-and-physiology-2e/pages/28-1-fertilization

Category icons are Lucide 1.72.0 paths converted into Android VectorDrawables.
SVG arcs are normalized to cubic paths with svgpath 2.6.0 to avoid Android's
incompatible parsing of compressed SVG arc flags. This is an authoring-time
conversion, not an application dependency.
The packaged `licenses/body-atlas-lucide.txt` retains the ISC and inherited
Feather notices. Icons are local assets and require no runtime network access.

## Nephron and Renal Cell Exploration

Four canonical structures extend the kidney hierarchy: the glomerular capsule,
proximal tubule, nephron loop and distal tubule. Native markers link them with
the glomerulus and collecting duct in a shared nephron overview. Selecting a
segment retains its identity and shows the explicit shared-image caption.
The proximal and distal segments link to their existing cell entries. Returning
from a cell restores its parent view rather than resetting to the catalogue.
In height-constrained layouts, the native marker column widens when necessary
to fit larger labels before positioning them; ordinary scroll layouts retain
the illustration-first proportions without reducing text size.

The generated plate is a simplified tube arrangement, not a histological section
or scaled cortical/medullary map. It omits capillary networks and the
juxtaglomerular apparatus. The collecting duct is shown as an associated
structure, not mislabeled as part of a single nephron. Microscopic cell entries
do not inherit this illustration as an image of an individual cell.

Seven independent four-stage mechanisms cover podocytes, mesangial cells,
proximal and distal tubular cells, collecting-duct principal and intercalated
cells, and urothelial cells. Titles scope the glucose-recovery, water-recovery
and type-A acid-handling examples; they do not describe every function of every
subtype. Each mechanism has its own source and remains qualitative.

`HealthAtlasRenal` centralizes the existing mass-balance equation. The native
balance display lists filtered, reabsorbed, secreted and excreted solute with
their directions and mg/min units. The response curve, output, reset and public
Agent preview use the same values. Zero transfers remain explicit; arrows are
directional rather than proportional flow gauges. Reabsorption is a fraction
of filtered load, and secretion is net added solute. This does not model water,
eGFR, segment-specific rates, drug clearance or an individual patient's kidneys.
No synthetic value is written into a health record.

Built-in image-generation prompt set for `res/drawable-nodpi/health_atlas_nephron.png`:
- An isolated simplified nephron with an associated collecting duct, transparent
  background and realistic teaching-plate shading; a red capillary tuft in a
  cutaway capsule, connected convoluted proximal tube, descending/hairpin/
  ascending loop, distal tube and a straight collecting outlet. No surrounding
  kidney, capillary network, labels, arrows or numbers.
- Cleanup edit preserving tissue and tube arrangement, removing exterior glow
  and adding transparent margins. Alpha and rendered-device checks verify
  usable image edges, not scientific or clinical validation.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-4-microscopic-anatomy-of-the-kidney
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-5-physiology-of-urine-formation
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption
- https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport

## Alveolar Exploration

The lung links to an alveolar cutaway with canonical respiratory-membrane and
pulmonary-capillary entries. These link to their relevant existing cell entries;
cell pages do not inherit the organ plate as an individual-cell image. The
caption identifies the shared schematic. Its thickness and colors are not
histological measurements. This increment brought the bitmap catalogue to fourteen plates.

A native gas-exchange diagram shows both diffusion directions simultaneously.
Fixed textbook partial-pressure examples use alveolar/incoming-blood values of
104/40 mmHg for oxygen and 40/45 mmHg for carbon dioxide. The diagram is separate
from the retained alveolar-ventilation equation: changing ventilation inputs
does not invent a new gas pressure or predict personal oxygen saturation.
Four selectable teaching focuses are not exclusive physiological time steps.
The diagram comes before ventilation controls. Selection changes color rather
than font metrics, keeping the measured stage rows stable during animation.
Animation stops on backgrounding; state restores per entity and research topic.
The public Agent preview includes directions, scope and reference without
including personal records. It omits these simulation details for other topics.

Five new cell mechanisms cover type I and II pneumocytes, ciliated airway cells,
an airway-specific goblet-cell example, and a human club-cell research overview.
The latter describes molecular function categories rather than claiming a
validated temporal process or transferring mouse regeneration results to humans.
The catalogue supports a strictly validated canonical PubMed reference override
while preserving existing OpenStax chapter references.

Built-in image-generation prompt for `res/drawable-nodpi/health_atlas_alveolus.png`:
an original isolated human alveolar cutaway, empty air space, thin pale-pink wall,
short duct above and a capillary network outside the wall containing red blood
cells; blue-violet incoming vessel and red outgoing vessel, transparent alpha,
realistic teaching-plate shading, uncropped margins, no labels, arrows, numbers,
glow or decorative particles. This is generated schematic art, not medical imaging.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/22-4-gas-exchange
- https://pubmed.ncbi.nlm.nih.gov/29874100/

## System Overview Plates

Six additional system-owned plates cover sensory organs, respiratory structures,
accessory digestive organs, selected endocrine glands, selected immune structures
and a skin cutaway. Together with the earlier gut and urinary plates, eight of
the fourteen navigation categories now own an overview. Twenty bitmap plates
are included in total. The cardiovascular category still explicitly shares the
heart plate; the remaining categories are not claimed to have completed art.

`HealthAtlasSystemPlates` registers only depicted structures. Dedicated organ
plates resolve first, so selecting lungs, liver or pancreas still opens its
existing detailed view. Shared images name their system and view scope. Composite
specimens are separate enlarged views, not a body-location map or equal-scale
anatomical section. The skin plate does not imply measured layer thickness.
Undepicted microscopic structures and cells do not inherit these pictures.

The existing native labels, zoom, fullscreen, layer selector, back stack,
per-entry simulation state, source links and scoped Agent preview are reused.
Label leaders route around other target markers using a small visibility graph
computed during layout, not during animation. Unobstructed leaders remain
straight. Unresolvable overlapping endpoints retain markers without a misleading
connector. Geometry tests cover clustered targets, reversed routes and scaling.
This addition does not change personal measurement access, create synthetic
patient records, introduce new numerical models or claim clinical validation.

### Asset Prompt Set

All six images were generated with the built-in image tool, not an external API.
Their final paths are under `apps/android/app/src/main/res/drawable-nodpi/`.
Common specification: original scientific educational 3D teaching illustration,
soft shading, transparent alpha, uncropped specimens, no baked-in text, arrows,
numbers or watermark. Native controls provide localized labels and navigation.

- `health_atlas_system_sensory.png`: separate eye cutaway, ear section, sagittal
  nasal cavity and dorsal tongue in a four-specimen composition.
- `health_atlas_system_respiratory.png`: sagittal upper airway and anterior lungs
  with diaphragm, explicitly a composite projection. A cleanup edit increased
  the empty margins while retaining the specimen and airway arrangement.
- `health_atlas_system_digestive.png`: salivary glands in a side-head view above
  a separate liver, gallbladder, bile duct, pancreas and duodenum arrangement.
- `health_atlas_system_endocrine.png`: separate enlarged pituitary/brain section,
  thyroid, adrenals above kidneys and pancreas; no implied anatomical scale.
- `health_atlas_system_immune.png`: separate thymus, spleen, lymph-node section
  and bone-marrow cutaway, with no implied physical connection between them.
- `health_atlas_system_skin.png`: angled block with epidermis, dermis, fat,
  follicle, sebaceous gland, sweat coil and surface duct. The final regenerated
  specimen preserves these structures; earlier discarded variants are not shipped.

References are the plate-specific OpenStax chapters linked in the registry.
The salivary-gland view additionally follows chapter 23.3:
https://openstax.org/books/anatomy-and-physiology-2e/pages/23-3-the-mouth-pharynx-and-esophagus

These generated schematics require further expert anatomical review before any
clinical or quantitative use. Whole-body nervous and vascular generations were
rejected by the image service and are not included or reported as completed.

## Two-compartment Distribution

The drug research panel adds a two-compartment mode alongside the existing
single-compartment elimination model. Its normalized initial amount is entirely
central: `A1(0) = 100`, `A2(0) = 0`. Transfers follow
`dA1/dt = -(k10+k12)*A1 + k21*A2` and
`dA2/dt = k12*A1 - k21*A2`. The eliminated amount is `100-A1-A2`.
The three constants are in inverse hours. The controls cover 0-3 inverse hours
in 0.01 increments and 0-48 hours in quarter-hour increments, solely as teaching
ranges. Values are amounts relative to the initial total, not concentrations.

`HealthAtlasDistribution` evaluates the closed-form linear solution. It uses
the stable product expression for the slower eigenvalue and `expm1` for the
early-time exponential difference. Zero outward transfer is evaluated as the
single-compartment limit, including coincident eigenvalues. Tests cover mass
conservation, positivity, irreversible transfer, zero elimination, limiting
equilibrium, equation derivatives and independent matrix-exponential fixtures.
The implementation is original Kotlin using the standard equations, not a
copy of the reference software. It does not bundle Monolix or an R runtime.

The native diagram shows bidirectional central/peripheral transfer and an
elimination arrow only from the central node. Three curves have distinct line
patterns as well as colors. Numerical summaries expose current values without
requiring color perception. Parameter edits update the local model, chart and
diagram; they do not rebuild the page. Curve samples are recomputed only when
rate constants change. No background simulation loop runs.

Each anatomy entry retains its own selected model and parameters across
navigation and recreation. Invalid saved arrays are rejected. The Agent preview
includes only the active drug model, its current inputs, values, assumptions
and source; physiology, aging and personal measurement flows do not inherit it.

This is a compartment model, not organ-resolved PBPK. Compartments group kinetic
behavior and are not labeled as individual organs. Absorption, repeat dosing,
nonlinear elimination, drug identity, patient fitting, therapeutic thresholds
and treatment predictions are excluded. No synthetic result becomes a personal
health record. Organ-resolved distribution and clearance remain separate work.

Reference for the linear amount equations and analytical treatment:
https://doi.org/10.12793/tcp.2019.27.2.43

## Musculoskeletal Views

The skeletal and muscular categories each add an anterior and a posterior
teaching plate. This brings the catalogue to twenty-four bitmap plates, with
ten of the fourteen categories owning a system overview. These generated
schematics are not patient imaging or a clinically validated anatomical atlas.

`HealthAtlasMusculoskeletalPlates` registers only visible surface structures.
Each system exposes a localized Front/Back selector. An individual structure
resolves only to views in which it is marked: selecting the trapezius opens
the posterior muscular view, never the anterior view. Undepicted deep muscles,
microscopic cells, cartilage and ligaments retain their existing catalogue and
mechanism views without borrowing an unrelated illustration. The diaphragm
and bone marrow retain their dedicated respiratory and immune contexts.
The generic tendon entry explicitly uses the heel tendon as its pictured example.

Switching perspective replaces only the artwork subtree, not the activity,
scroll container, primary tabs or Agent button. Each entry remembers its own
stable view key across navigation and activity recreation; unrelated or invalid
saved keys fall back to that entry's valid default. Fullscreen, zoom/reset,
localized native hotspots, source links and the existing cell navigation remain
available. The public Agent preview includes the currently selected view and
its source, not a stale anterior caption. Personal measurement access and
consent are unchanged. No synthetic value is stored in a health record.

The plates themselves do not add a biomechanical numerical model. Existing sourced
function stages, mechanism playback, related measurements and research modes
remain available. Deep-layer illustrations, joint-specific mechanical models
and expert anatomical review are separate work; the static elbow example below
is one subsequent model, not a replacement for that broader work.

### Asset Prompt Set

Built-in image generation was used, without an external image API. The final
assets are under `apps/android/app/src/main/res/drawable-nodpi/`:

- `health_atlas_skeleton_front.png`: original clinical educational full adult
  skeleton, anterior anatomical position, head to feet, arms apart, palms
  forward; ivory bones with realistic subtle shading, visible skull, clavicles,
  sternum, ribs, pelvis and paired limb bones, hands and feet. Tall centered
  transparent cutout, no skin, organs, labels, arrows, numbers or watermark.
- `health_atlas_skeleton_back.png`: posterior full skeleton, centerline cervical,
  thoracic and lumbar vertebrae and sacrum, scapulae over ribs, pelvis and rear
  limb bones; ivory three-dimensional clinical teaching illustration. Transparent
  portrait composition, no skin, organs, text, markers, frames or watermark.
- `health_atlas_muscle_front.png`: anterior superficial muscular-system model,
  head to feet, standing with arms apart and palms forward. Red/pink muscle
  fibers, pale tendons, clear pectoralis, deltoids, biceps, rectus abdominis,
  external obliques and quadriceps. Neutral medical shading and proportions,
  transparent portrait cutout, no skin, gore, sexual anatomy or baked-in labels.
- `health_atlas_muscle_back.png`: posterior superficial muscular-system model,
  head to feet, arms apart, visible trapezius, posterior deltoids, triceps,
  latissimus, gluteus maximus, hamstrings, gastrocnemius and heel tendons.
  Red/pink fibers and pale tendons, no deep cutaways, skin, gore, text, markers
  or watermark; transparent portrait cutout.

Anatomical references are linked rather than bundling textbook artwork:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/7-1-divisions-of-the-skeletal-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/11-2-naming-skeletal-muscles
- https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs

## Static Elbow Mechanics

The skeletal and muscular categories, biceps brachii, humerus, radius and ulna
expose one explicitly scoped elbow example. A horizontal rigid forearm is in
static equilibrium with vertical forces and a relaxed antagonist. Controls vary
external mass (0-10 kg), its distance from the elbow (20-50 cm) and the biceps
perpendicular lever arm (20-60 mm). Forearm mass is fixed at 2.5 kg, its centre
of mass at 0.16 m and gravitational acceleration at 9.8 m/s^2. These are teaching
assumptions, not patient measurements or safe lifting ranges.

The original pure Kotlin model converts distances to metres and evaluates
`B = (armWeight * 0.16 + loadWeight * loadArm) / muscleArm` and
`E = B - armWeight - loadWeight`. B acts upward; E acts downward throughout
the supported input domain. The default produces B = 470.4 N, E = 406.7 N and
opposing moments of 18.816 N m. Tests independently check reference values,
unit conversions, zero external load, all control corners, force/torque balance,
monotonic responses and invalid saved states.

An original native free-body diagram uses labeled arrows and numerical text;
arrow length is not a force scale. Lever-arm locations update with the controls.
The response curve is muscle force versus external mass, not time or a health
trend; its labeled vertical range adapts to the current geometry. Updates retain
the page and controls. Parameters remain scoped to each entry across navigation
and recreation. The Agent preview receives the active inputs, numerical forces,
assumptions and source; unrelated cells, drug and aging topics do not inherit it.

No animation implies a dynamic mechanical solution. Acceleration, muscle-length
dependence, fatigue, co-contraction, individualized geometry, injury prediction
and rehabilitation advice are not modeled. Synthetic outputs never become health
records. Textbook artwork and prose are not bundled. Equation reference:
https://openstax.org/books/college-physics-2e/pages/9-6-forces-and-torques-in-muscles-and-joints
