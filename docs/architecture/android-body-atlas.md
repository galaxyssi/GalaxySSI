# Android Body Atlas

The public teaching catalogue contains 14 navigation categories, 161 canonical
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

Cardiac output, ventilation, renal solute balance and potassium equilibrium
potential are fixed-input teaching equations. Other sequences are qualitative,
not validated quantitative patient models.
No organ score, biological age, drug dose or treatment outcome is inferred.

## Interactive Physiology

`HealthAtlasPhysiology` provides three independently bounded teaching models:

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

Seventeen canonical entries expose these associated processes. Tubular cells
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

- Extend the anatomical illustrations and selectable structures beyond the
  whole-body, heart, brain, lungs, liver, kidney and beta-cell views. Each image must depict its named entity;
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

## Cell-specific processes

The thirty core cells now have their own four-stage teaching processes and
chapter references in the catalogue, rather than reusing a system-level cycle.
These include the ten blood/immune examples, three neural examples, three
muscle types, four skin/connective/metabolic examples, four bone/cartilage
examples, endothelium, hepatocytes, beta cells, enterocytes and two gametes.
The loader rejects a cell-specific mechanism assigned to a different entity.
Other cell subtypes still use broader pathways until dedicated content is
reviewed; this is not a claim of complete single-cell biology coverage.

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
