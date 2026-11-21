# Android Body Atlas

The public teaching catalogue contains 14 navigation categories, 177 canonical
organ/structure entries, 14 tissues, 107 cell types or subtypes, and one platelet-fragment
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
potential, oxygen binding, static elbow balance, ideal tube flow, eye focus and
ideal middle-ear transfer are teaching equations. Germline
stage tables expose chromosome and DNA counts. Other sequences are qualitative,
not validated quantitative patient models.
No organ score, biological age, drug dose or treatment outcome is inferred.

## Tissue Layer

The organ catalogue has adjacent Organ and Tissue views. The Structure tab
of an organ detail offers Organ, Tissue, and Cell layers. Changing that layer
keeps the scroll parent and Agent action mounted. Both selectors survive
activity recreation, and returning from a child restores the parent layer.

Four tissue families are represented by 14 canonical entries, connected to
59 organ/structure examples and 26 cell examples. Graph validation requires
distinct `locatedIn` organ IDs with a shared category and `related` cell IDs
on each tissue. Each tissue owns a localized four-stage function sequence.
An organ without an explicit link shows an empty state rather than inheriting
unrelated tissues from its system.

Each tissue has an original vector schematic and hotspot links to depicted
cells. These are instructional drawings, not microscopy, and the four steps
are qualitative, with no time or clinical scale. Knowledge-only Agent previews
carry the selected tissue's examples, source and, when relevant, current step.
No patient values are computed or assigned to tissue entries.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-1-types-of-tissues
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-2-epithelial-tissue
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-3-connective-tissue-supports-and-protects
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-4-muscle-tissue-and-motion
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-5-nervous-tissue-mediates-perception-and-response

## Respiratory And Renal Cell Plates

Twelve distinct plates add 25 localized landmarks for airway epithelium,
type I and II pneumocytes, glomerular cells, tubular and collecting duct
epithelium, and a superficial urothelial umbrella cell. The intercalated
cell plate explicitly depicts a type A example.

The podocyte walkthrough shows the fenestrated endothelium, shared basement
membrane and filtration slits together at each step. It shows how filtrate
enters the capsular space, not a patient filtration rate or barrier dimension.
The structure references are the OpenStax respiratory anatomy and microscopic
kidney chapters; the spherical interface model is linked to
https://pubmed.ncbi.nlm.nih.gov/20724566/.

## Digestive Cell Pathways

Thirteen cell plates cover the remaining cells linked to the digestive tract
or its accessory organs. The islet plate adds four links to alpha, beta, delta
and PP cells. Twenty-seven structural callouts distinguish secretion surfaces,
granules and nearby tissue. Islet colors denote cell examples, not actual
staining, abundance or fixed placement in human islets.

The pancreas compares delivery to the duodenum through the duct with hormone
secretion toward local capillaries. The islet compares four distinct cell
roles and links each step to the corresponding structure page. The steps
describe functions, not a timing model. Hormone destinations are separate
from the synthetic ductal-fluid calculation.

## Endocrine Glands And Cells

Four gland plates and fourteen cell plates add 37 labeled structures and four
catalogue links. Cell shape and color are illustrative, not diagnostic
histology. The thyroid panel separates follicular cells from C cells, and the
posterior neck view shows a common, not universal, parathyroid arrangement.

Four independent pathways cover thyroid feedback, PTH regulation of calcium,
pituitary anterior and posterior lobe signaling, and adrenal cortex and medulla
signaling. Mechanism stages choose their own cell or organ links. The medulla
and posterior lobe paths are not represented as steps in the ACTH or anterior
pituitary branches.

## Neural And Sensory Atlas

Fifteen plates cover the remaining unillustrated nervous and sensory cells and
the new retinal bipolar and AII amacrine entries. One additional plate shows
the retina in section, with oppositely oriented arrows for incoming light and
neural signal. The previous view of its position in the eye remains selectable.
Thirty-four bilingual landmarks explain structures, and the new retina circuit
distinguishes the example rod ON relay through AII and ON cone bipolar cells
from cone transmission. These are representative pathways, not a wiring map.

## Microscopic Artwork Coverage

Every one of the 107 named cell entries now has a dedicated illustration, as
does the separately classified platelet fragment. The final 21 cell plates
show tissue context for marrow and immune cells, reproductive tissues, skin
appendages, the muscle satellite-cell niche and tendon cells within collagen
bundles. Color and shape are not
diagnostic identifiers for T-cell subtypes or developmental stages.

The hair follicle and eccrine sweat gland have their own sections with links
to matrix and secretory cells. The sweat walkthrough distinguishes secretion,
transport, release and evaporation; playback does not give real durations.

## Immune And Lymphatic Organs

Nine entries now open original sectional or regional artwork instead of relying
on the parent immune overview: red marrow, thymus, spleen, lymph node,
collecting lymphatic, thoracic duct, palatine tonsil, adenoid, and ileal
Peyer patch (one example of gut-associated lymphoid tissue). Thirty bilingual
landmarks explain depicted compartments; markers lead to existing cell or
vessel entries, without creating duplicate anatomical identities.

Each lesson has four localized steps. The lymph node and thoracic duct show
one directed fluid route; other plates highlight the region relevant to a step.
Spleen filters blood rather than lymph, thymus supports T-cell maturation, and
the tonsil/adenoid examples distinguish palatine crypts from nasopharyngeal folds.
The thoracic duct illustration marks the patient's left and notes anatomical
variation. Phases restore by entry and are shared with Mechanism Research.

The independent valve example shows pressure difference and open resistance,
forward flow, and the signed hypothetical flow without the valve. Slider
bounds are synthetic, not reference intervals. No simulation reads or writes
personal health measurements. See the
[anatomy chapter](https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems)
and the [measured-valve modeling study](https://pmc.ncbi.nlm.nih.gov/articles/PMC4500195/)
for anatomy and the limitations of an ideal directional element.

## Editorial Illustration Migration

The first style batch replaces the whole-body, heart, lungs, liver, kidney,
brain and intestinal overview bitmap plates with original, softly shaded
educational illustrations rather than specimen-like renders. The canvases
keep their previous dimensions and alpha framing. The canonical overlay
coordinates, zoom, section navigation, localized labels, sources and
personal measurement handling are unchanged. The references supplied for
art direction are not packaged; no text or health claims are baked into
the illustrations.

The second batch applies the same treatment to the pancreas and duodenum,
urinary tract, nephron, alveolar section, pancreatic beta cell, erythrocyte
and neuron. In particular, the open spaces between the ureters and nephron
tubules remain transparent. The existing gas exchange animation and cell
mechanisms still use their own data and controls.

The third batch restyles the six raster system overviews (sensory,
respiratory, digestive accessory organs, endocrine, immune, and skin) and
both skeletal and muscular views. The muscle artwork uses a covered teaching
mannequin, with the gluteal region shown by markings on the garment. Tap
targets are recalibrated where the painted muscle, tendon, gland or cartilage
differs from the old plate. The view keys and the destinations are unchanged.

The native section renderer traces only the traveled portion of the active
stage path and aims a contrasting arrow along its tangent. It does not add
an independent animation or imply a real material speed or quantity. For
lessons without a directional path, existing structure highlights remain.
All 24 original bitmap plates have now been restyled. The separately
authored vector plates and native simulation artwork are a separate
migration.

The sensory vector pass applies soft shading to the ear and eye sections, the
cochlear hair cell, and the retinal layers without changing the underlying
paths or structure hotspots. The ear's four air-conduction steps now run over
the original wide cross-section, separately from the ideal middle-ear
pressure model. The retinal cross-section highlights the region represented
by the selected circuit stage, and the circuit still supplies the full
relay labels and cell links. Neither animation measures personal function.

The illustrated hearing update replaces the ear vector with a transparent
3:2 painted cutaway, using the same drawable for labeled structure,
fullscreen, and playback. The five navigation anchors and the four
air-conduction tracks are calibrated to the new illustration independently.
The last track terminates on the auditory nerve. Retinal circuit destinations
also use shaded plates for rods, cones, bipolar cells, AII amacrine cells,
ganglion cells, and the pigment epithelium; their native geometry and
semantic callouts are unchanged.

The painted eye cross-section also retains a transparent 3:2 composition.
The eye structure, fullscreen, and retinal location views share the plate;
the cornea, lens, and retinal lining links are recalibrated to the artwork.
The optical ray model remains separate. For this plate, the ear, and the
multi-panel sensory, immune, and endocrine overviews, callouts use separately
measured left and right rails. Leader detours stay in the half of the image
that contains their target, and labels retain their native touch targets.

The cochlear inner hair cell, rod photoreceptor, and cone photoreceptor
use separate painted 2:3 plates. Their existing explanatory stages
highlight the selected cell region on the portrait without representing
measured kinetics. The hair-cell view distinguishes its afferent contact
from the receptor itself; the rod and cone retain their distinct terminal
callouts. The rod photon model remains independent of the stage player.

The nervous-system overview uses a posterior painted view of the brain,
spinal cord, and sample peripheral nerves. Its five existing links are
calibrated to the painted positions. The circulatory and both reproductive
overviews use shaded fills while retaining their native anatomy paths,
viewports, and callout locations.

All 14 tissue plates and nine lymphatic section plates use softly shaded
native vector surfaces. Broad fibers and tissue layers retain their original
contours, while thin boundaries, nuclei, valves and pathway linework remain
distinct. Artwork identities, viewports, localized callouts and stage paths
are unchanged. The colors denote structures schematically, not stain results
or quantitative measurements.

The heart cutaway is a painted restyle of the original section, not a new
clinical model. The four chambers and two outflow vessels keep their
canonical destinations. The same calibrated leaflet positions drive both
the structure callouts and the four-state valve demonstration. Blue and rose
distinguish the two circulation sides without encoding oxygen saturation.

The neutrophil and macrophage use separate painted plates. The neutrophil
retains one connected lobulated nucleus and peripheral granules; the
macrophage retains its membrane extensions and representative vesicle. The
macrophage stage player shares the painted cell and moves a generic particle
and teaching overlays along the existing playhead. The visual sequence is
qualitative: its timing, geometry, colors and particle size are illustrative.

Eosinophil and basophil portraits distinguish coral granules and a connected
bilobed nucleus from dark granules that partly cover the basophil nucleus.
Three distinct illustrated scenes follow the existing granulocyte lessons:
neutrophil migration and uptake, eosinophil contact and granule release, and
basophil mediator release with a local vessel response. Each scene follows the
current playhead, restores per entry, and reports the current stage to
accessibility services. None models clinical doses, timing or measurements.
The public Agent handoff retains the scope of just the selected scene.

Painted monocyte, dendritic cell, and plasma cell plates retain their
individual structural landmarks. Their separate scenes distinguish tissue
recruitment, antigen presentation, and antibody secretion. Links open the
canonical macrophage, T-cell, and B-cell pages without changing the source
lesson's stage. The shared playhead and framing retain the same behavior for
granulocytes. These are qualitative examples rather than measurements or an
exhaustive set of possible cell fates.

The 12 core immune and blood plates now all have painted artwork and their own
qualitative stage renderers. T-cell and B-cell plates preserve their distinct
schematic receptor symbols without implying a diagnostic distinction by shape.
The NK response, megakaryocyte platelet formation, and platelet plug formation
are separate scenes. The resting platelet is an anucleate fragment; its
activated form is drawn separately in the plug example. The new stage shapes
and timings do not model a patient, a drug or a coagulation test.

The 14 alimentary section plates and 14 related digestive-cell or gland
plates now use softer colors. The tooth and jejunal villi use painted
cutaways with recalibrated markers and a square lesson frame. The other
plates retain their exact vector paths, marker destinations and teaching
coordinates while broad tissue surfaces are shaded and fine structures
remain visible. Existing bolus and bowel paths are unchanged.

## Alimentary Canal Sections

Fourteen digestive entries now have their own source-linked diagrams, from
oral cavity and teeth through the esophagus, stomach, three regions of the
small intestine, the large intestine, cecum, appendix, colon, rectum, and anal
canal. Forty-seven bilingual annotations explain named structures and 29
canonical links open the depicted organ, adjacent duct, or cell. The parent
digestive and pancreatic maps retain their own identities and navigation.

The section renderer shares step, scrub, playback, accessibility, and restore
behavior with the lymphatic sections. Six alimentary diagrams show a moving
marker through a representative lumen path; the others highlight structures
during their specific lessons. No simulated path reports real transit time.

The small intestine and jejunum show equal, non-overlapping cylindrical villi
on a 1 mm^2 patch. In the model, the exposed tip replaces the same footprint
at the base; only the side contributes extra area. With density N per mm^2,
radius r in mm, and height h in mm, the area ratio is `1 + N * 2*pi*r*h`.
The top and side views share a scale, and the chart varies density with radius
and height fixed. Folds, microvilli, transport, and individual absorption
are excluded. See the [small intestine anatomy chapter](https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines)
and [human mucosal morphometry](https://pubmed.ncbi.nlm.nih.gov/24694282/).

## Interactive Physiology

`HealthAtlasPhysiology` provides seventeen independently bounded teaching models:

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
- Static elbow balance relates external load and lever arms to muscle force;
  its assumptions and references are detailed below.
- Ideal vessel-segment flow relates pressure drop, radius, length and viscosity
  to flow, resistance, speed and wall shear; its assumptions are detailed below.
- Eye optics relates object distance and equivalent optical power to the
  signed image offset from a fixed retinal plane.
- Ideal middle-ear transfer relates the effective eardrum area, stapes
  footplate area and ossicle lever ratio to pressure gain.
- Ventricular ejection fraction divides ejected stroke volume by the sum of
  that volume and the end-systolic volume. The two inputs are synthetic.
- Axon signal travel time uses distance divided by constant speed, with
  centimetres converted to metres and seconds converted to milliseconds.
- The type II pneumocyte page illustrates the Young-Laplace pressure difference
  across a single spherical interface, 2 times surface tension divided by radius.
  It compares the selected radius with twice that radius at the same tension.
  This omits tissue elasticity and alveolar interdependence and is not a
  measured breathing pressure or a ventilator model.
- Bicarbonate mixing combines a fixed synthetic base stream and a variable
  ductal stream. It divides total bicarbonate delivered per minute by combined
  volumetric flow. It does not predict pH, neutralization, or individual
  pancreatic function.
- A linear feedback example in the thyroid panel divides the initial
  dimensionless signal by one plus feedback strength. The result is distinct
  from TSH or thyroid hormone measurements and never enters the health record.
- The rod cell panel illustrates Poisson absorption over a fixed window:
  one minus the probability of zero events. It reports absorption probability,
  not perceived brightness, visual acuity or a personal vision threshold.
- The sweat gland panel applies an example latent heat of 2,426 J/g to a
  synthetic evaporation rate at around 30 C. Only evaporated mass contributes
  to this calculation; it is not a whole-body cooling or dehydration estimate.
- The collecting lymphatic example applies an ideal check valve: forward
  flow is `max(delta pressure, 0) / open resistance`. It does not represent
  contractions, compliance, leakage, or a measured flow.
- Villus geometry shows synthetic area amplification, not an absorption rate.

Fifty-two canonical entries expose these associated processes. Tubular cells
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

The ten macroscopic circulation entries use a native double-circulation
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

### Heart Section and Valve Timing

The heart retains its original external drawing and adds a frontal teaching
section with six hotspots for the two arterial outlets and four chambers.
The depicted anatomical right is on the viewer's left. The valve group
uses the same original section and shows only the four valve landmarks.
Each newly named structure has its own function description and four steps.
The section selector restores on back navigation and activity recreation.

The valve simulation shows the pressure-driven states of all four valves
with both drawn indicators and text. Inlet valves open in ventricular filling;
outlet valves open in ejection; both sets are closed in the two constant-volume
phases. The selected phase is synchronized with the existing step and playback
controls. Educational phase lengths do not represent actual timings.

Only the ventricular entries have the ejection fraction controls. Their
independent state and fixed-axis graph explain the volume relationship without
inferring any personal ejection fraction, diagnostic threshold or outcome.
The public Agent preview uses the selected valve state or teaching model and
links its source. Personal health records and the disclosure flow are unchanged.

- https://openstax.org/books/anatomy-and-physiology-2e/pages/19-3-cardiac-cycle
- https://openstax.org/books/anatomy-and-physiology-2e/pages/19-4-cardiac-physiology

Each entry opens a native three-tab research surface. Physiology retains the
entry's teaching sequence and controls. Drug pathways show a clearly labeled
whole-body ADME overview with links to relevant structures, plus a normalized
single-compartment first-order elimination explorer. The latter starts at 100%
and has no drug identity, dosage, patient data or therapeutic thresholds.
Its half-life and elapsed-time controls restore independently for each entry.
Drilling into a structure and returning restores the research tab and inputs.

The aging tab exposes the 12 research themes from the 2023 Cell framework.
Each has four localized, selectable conceptual steps, a short explanation and
a canonical anatomy example, not a diagnosis for the selected structure.
The local topic and step follow the original entry across tab changes, anatomy
drilldown/return and activity recreation. Native process labels measure
multiline content; the diagram has no time axis or playback clock.

Two themes include primary human observational evidence with sample, finding
and limits. The telomere card uses Daniali et al. (87 adults, four tissues),
including the reported leukocyte-versus-tissue correlation range; it does
not portray a longitudinal trajectory. The senescence card uses Liu et al.
(170 donors, two cohorts) and distinguishes age-associated expression in
blood T cells from counting senescent cells in an organ. Neither is a clinical
threshold, an intervention result or a validated personal aging test.

The Agent preview carries only the active aging topic, selected conceptual
step and associated sources; switching to physiology or drug pathways omits
aging context. None of these tabs reads personal health data, writes study
numbers to records or infers a biological-age score.

Research references:
- https://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics
- https://pharmacologyeducation.org/clinical-pharmacokinetics/
- https://pubmed.ncbi.nlm.nih.gov/36599349/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC3615479/
- https://pubmed.ncbi.nlm.nih.gov/19485966/

## Design Coverage and Remaining Work

The Function tab for skeletal muscle tissue, white adipose tissue and
adipocytes includes a five-chapter continuously drawn insulin and GLUT4
lesson. Skeletal myocytes offer it alongside their default contraction lesson.
Structures stay in view as the ligand approaches, the PI3K-dependent lipid
signal recruits AKT, and the vesicle opens and flattens into the cell membrane.
Illustrated glucose crosses GLUT4 only after fusion is complete. The
five-chapter playhead is independent of the four-step
physiology model. Playback pauses on navigation or backgrounding; the
current chapter and two primary sources go into the public Agent preview.
The pancreatic beta cell keeps its own secretion mechanism rather than
inheriting the target-cell lesson. The animation is qualitative and does not
convert playback time or particle count into physiological measurements.

Evidence: https://pubmed.ncbi.nlm.nih.gov/19188436/ and
https://pmc.ncbi.nlm.nih.gov/articles/PMC1899973/.

The conducting airway has a separate five-stage mucus clearance lesson:
particle capture, goblet-cell secretion, coordinated cilia, conveyance
toward the throat, and swallowing. A lung locator stays visible above the
animated cross-section. Trachea and bronchi keep their breathing lesson;
the airway lining and its ciliated cells open mucus clearance by default.
Alveolar gas exchange is not depicted as having a mucus conveyor.
Evidence: https://pmc.ncbi.nlm.nih.gov/articles/PMC3633213/ and
https://pmc.ncbi.nlm.nih.gov/articles/PMC4504973/.

The tissue catalogue links cardiac muscle, alveolar lining and renal
tubular epithelium to matching organ lessons. Separate five-stage lessons
show capillary exchange, platelet plug formation, intestinal smooth muscle
propulsion, tendon force transfer, articular cartilage loading and recovery,
alveolar surfactant and intestinal absorption. The absorption lesson
distinguishes soluble nutrients going to blood from lipid particles taking
the lymphatic route. Organ entries preserve their default lessons and
expose the focused mechanisms as additional choices. Structure and
quantitative simulations remain independent of visual playback.

The knee-motion lesson links the joint, femur, tibia, quadriceps and
hamstrings. It maintains the same side cutaway through flexion, patellar
glide and extension, with a separate cartilage loading lesson on the
patella. Playback pose and highlighted pull directions are illustrative, not
measurements or exercise prescriptions.

The heart and cardiac muscle offer an electrical-signaling lesson alongside
the existing pumping cycle. Its five chapters keep the cardiac conduction
path and a ventricular muscle cell visible, then distinguish activation,
calcium-linked filament sliding and relaxation. The standalone
cardiomyocyte entry opens this process directly.

New focused entries for aortic and pulmonary outflow, type I alveolar cells
and renal structures start at their relevant chapter in a shared lesson.
Users can return to the beginning or select another chapter. A saved
playhead, including zero, always takes precedence over this initial chapter.

The regional lessons also show oxygen transport in red cells, the calf
venous pump, pleural coupling, urine transport and storage, salivary
secretion, the hair follicle cycle, parathyroid calcium feedback and milk
production and release. These are separate qualitative explanations, not
clinical models. Salivary and mammary cells open at their own role in the
process; nephron filtration, whole-lung ventilation and other broader
lessons retain their independent playheads.

Nine existing painted cell mechanisms also run in the Function player.
Each retains its own four-stage artwork and headings, with localized
captions, timeline playback and source links. The Function and Simulation
screens use separate renderer instances and store their playheads
independently. Platelet production remains distinct from the platelet
fragment's hemostasis lesson.

Dedicated lessons cover cerebellar coordination, astrocyte support,
brainstem breathing rhythm, voice production, melanin transfer, dermal
matrix renewal, spleen filtration and thymic selection. These qualitative
lessons open from their matching organs, tissues or cells. They do not
replace the broader mechanisms for ventilation, skin barrier and immunity.

The arterial lesson pairs an aortic locator with cross-section and
lengthwise cutaways. Wall expansion, pulse-wave travel and blood flow are
separately marked. The aorta's original ejection lesson remains available;
the vessel-family entry also links to venous return and capillary exchange.
The cutaways use qualitative motion, not personal flow or pressure values.

Separate close-ups show articular chondrocytes maintaining their matrix,
chromaffin cells releasing hormones in the adrenal medulla, gastric
parietal cells secreting acid, and blood cells forming in red marrow.
Related entries link to these lessons without reassigning unrelated cells.
The coronary lesson links to the heartbeat while separately showing perfusion
during contraction and relaxation and drainage through the coronary sinus.
The podocyte lesson shows the three layers of the filtration barrier rather
than attributing whole-nephron transport to one cell.

The endometrial lesson separates epithelial repair from stromal growth and
uses different starting chapters for the two cells. The bilateral pupil
reflex is distinct from vision and the nerve-transit model. The sebaceous
lesson shows normal hair-associated secretion without replacing hair growth
or sweat cooling, and the sebocyte opens at lipid accumulation.

The cerebral lesson follows a voluntary reach, with separate sensory
registration, target integration, motor output and ongoing feedback.
The autonomic lesson compares the sympathetic and vagal relays to the
heart without changing the heartbeat, coronary or cranial-reflex lessons.
Gastric chief-cell secretion is separate from acid secretion. Pancreatic
acinar cells have a digestive enzyme lesson that is separate from the islet
and ductal models. The tonsil example distinguishes palatine crypts from
adenoid folds. The nail example explains formation in the matrix and support
by the bed, not growth at the free edge.
The nail and sebaceous-gland Structure tabs have dedicated two-sided
cutaneous cutaways. Their callouts explain local anatomy; the sebaceous
plate also opens the matching follicle and sebocyte entries.
The sinus lesson locates the four sinus groups before showing clearance
in one maxillary sinus. The tooth lesson shows cutting and grinding without
changing the existing mouth and digestion lessons.

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

- Extend the 181 anatomical, tissue and cellular illustrations and selectable structures to the
  remaining organs and tissue structures. Each image must depict its named entity;
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

## Blood and Immune Cell Illustrations

Twelve original vector plates show representative neutrophils, eosinophils,
basophils, monocytes, macrophages, T cells, B cells, natural killer cells,
plasma cells, megakaryocytes, dendritic cells, and the platelet fragment.
The 25 visible landmarks open localized explanatory notes without navigating
to a fictitious organelle entry. T- and B-cell illustrations use the same
representative lymphocyte body with different schematic receptors; they
cannot be used to distinguish the cells by blood smear appearance. The
resting platelet is an anucleate fragment, not a twelfth cell type.

The macrophage simulation draws the four selected phases on a native canvas:
encounter, enclosure, digestion, and debris handling with signaling. The
picture and accessibility description track the existing stage controller and
saved selection. This diagram describes a generic particle and does not
simulate physiological time, measurements, or a patient-specific outcome.
Knowledge-only Agent previews include the selected cell's public labels and
source, plus the simulation stage when applicable.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets
- https://openstax.org/books/anatomy-and-physiology-2e/pages/21-2-barrier-defenses-and-the-innate-immune-response
- https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types
- https://openstax.org/books/anatomy-and-physiology-2e/pages/21-4-the-adaptive-immune-response-b-lymphocytes-and-antibodies

## Core Cell Structure Coverage

All 30 core cell types now have their own structure illustration. The 18
added plates include nervous, muscle, epithelial, connective, bone, cartilage,
vascular, liver, intestinal, and reproductive cells. All 39 new landmarks
open localized notes. Adjacent extracellular matrix, blood vessel, and
supporting cells are shown for context without becoming extra catalogue
identities. The remaining extended catalogue is not implied to have individual
artwork. Existing measured health indicators remain separate.

The skeletal muscle cell has an interactive sliding-filament diagram that
uses its four existing excitation, calcium, contraction, and relaxation
stages. At its illustrative contracted stage the Z-disc spacing is 180
drawing units instead of 250 (72%), but neither filament length changes.
This is a dimensionless example, not a force model or a typical clinical
shortening percentage. The ratio and drawing follow saved phase selection
and are only included in the current skeletal cell's public Agent context.

- https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue
- https://openstax.org/books/anatomy-and-physiology-2e/pages/10-3-muscle-fiber-contraction-and-relaxation
- https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin
- https://openstax.org/books/anatomy-and-physiology-2e/pages/4-3-connective-tissue-supports-and-protects
- https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure
- https://openstax.org/books/anatomy-and-physiology-2e/pages/28-1-fertilization

## System Overview Coverage

All 14 navigation categories own an overview illustration. Four new original
schematics cover central and peripheral nervous anatomy, pulmonary and systemic
circulation, the testicular tract in side view, and the ovarian tract in front
view. The 23 hotspots match drawn landmarks and reuse canonical catalogue
entries. Dedicated child artwork still takes precedence, so selecting the
heart, lungs, brain, aorta, or pulmonary trunk does not replace their detail
plates with an overview. Where a child uses system art, the caption identifies
that system rather than claiming to depict an isolated organ.

These teaching plates summarize selected relationships, not all anatomy or
patient geometry. The circulatory illustration simplifies vessel branching.
The reproductive views do not claim to track a person's cycles or fertility.
The nerve model is available in the cranial, spinal and peripheral nerve
entries. Its response chart holds the selected speed fixed and rescales the
vertical axis to that curve. It excludes synaptic delay and clinical test
interpretation, and does not replace the existing potassium equation.

References:
- https://openstax.org/books/anatomy-and-physiology-2e/pages/12-1-basic-structure-and-function-of-the-nervous-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/20-5-circulatory-pathways
- https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system
- https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system
- https://www.ncbi.nlm.nih.gov/books/NBK10921/

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
the total to 37; five respiratory-related cells extend that to 42, and twelve
reproductive/supporting cells extend it to 54. The complete microscopic catalogue
increment below adds the remaining 51 cell types and the platelet fragment.
This is not a claim of complete single-cell biology coverage.

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

## Reproductive Cell Mechanisms

Twelve additional cell-owned mechanisms replace inherited system-level stages:
Sertoli, Leydig, spermatogonium, spermatocyte, granulosa, theca, ciliated tubal,
endometrial epithelial, endometrial stromal, mammary luminal, myoepithelial and
trophoblast cells. Each has four independently localized, sourced function
stages. The mammary mechanism is explicitly one example of myoepithelial function,
not a claim that all myoepithelial cells respond to the same signals. The catalogue
reached 54 independent cell mechanisms at that increment, before the remaining
microscopic entries described below were expanded.
Obsolete OpenStax male/female chapter slugs are replaced by the current
testicular/ovarian chapter names. Stromal decidualization cites the review at
https://pubmed.ncbi.nlm.nih.gov/25141152/.

Four germline entries additionally expose original native chromosome/DNA
schematics and discrete stage-end counts. `HealthAtlasGermline` tracks one
selected cell or genome, not the sum of all meiotic daughters. The typical human
states are 46 chromosomes/46 DNA molecules before replication, 46/92 after
replication, 23/46 after meiosis I and 23/23 after meiosis II. A sperm always
contributes only the paternal 23/23 in its existing fertilization mechanism.
The oocyte sequence starts with a secondary oocyte (maternal 23/46), completes
meiosis II after activation (maternal 23/23), and only its final zygote stage sums
both parents (46/46, before the first zygotic DNA replication).

The diagram draws a few representative replicated or unreplicated chromosome
symbols, not an anatomical cell illustration or a complete karyotype. The scope
label distinguishes maternal, paternal and combined counts. No continuous count
interpolation, anaphase intermediate, meiotic arrest duration, recombination,
abnormal karyotype, individual genetics or fertility prediction is modeled.
The general stage-count reference is linked, not copied or bundled:
https://openstax.org/books/biology-2e/pages/11-1-the-process-of-meiosis.

Stage selection, playback and reset use the existing simulation controller.
The current stage and transport controls precede the count diagram; extended
scope notes follow the interactive content instead of pushing controls away.
Only stage-boundary changes update the numeric subtree; no independent animation
or background job is added. Per-entry restoration and on-stop playback pause
remain intact. The public Agent preview includes the active count, its scope and
reference only in the selected physiology flow. Drug/aging topics and unrelated
cells do not inherit it. No simulated value is written to personal records.

No reproductive-system anatomical overview artwork is added by this increment.
An attempted internal-organ plate was rejected by the image service and is not
included or represented as complete. Existing illustration and expert-review
gaps remain; the following increment closes the generic microscopic-process gap.

## Complete Microscopic Process Catalogue

All 107 named cell entries and the separately classified platelet fragment now
own a four-stage English/Chinese mechanism. The 52 newly expanded entries cover
immune and hematopoietic, neural, sensory, vascular, digestive, endocrine, skin
and musculoskeletal functions. Each process has its own title, stage resources
and public source. The catalogue loader and packaging tests reject a missing
mechanism, a fallback to a system process, a mismatched cell/fragment kind or
assignment to another entity. Platelets remain fragments, not another cell type.

Existing native stage controls provide selection, playback, pause, reset and
per-entry restoration. Agent context carries the selected entity, stage and
source; no personal observations are automatically attached. Stage timing is
an illustrative sequence, not measured biological duration. Processes with
multiple possible functions explicitly select an example, including I-cell
CCK secretion, adrenal zona fasciculata cortisol synthesis, eccrine cooling,
ependymal ciliary transport and retinal pigment epithelial clearance.

The content distinguishes photoreceptor hyperpolarization from ganglion-cell
action potentials, prolactin-driven milk synthesis from milk ejection, and
platelet aggregation from the coagulation process that stabilizes the plug.
Pancreatic polypeptide roles are described with research uncertainty. No new
patient-specific scores, treatment recommendations or numerical models are
introduced. Dedicated artwork for every cell, comprehensive molecular pathways,
organ-specific numerical models and expert anatomical/content review remain
separate work. This closes catalogue function coverage, not the entire atlas.

Sources are linked in each mechanism; textbook prose and figures are not copied.
Specific review references complement the OpenStax chapters:

- Photoreceptor signaling: https://pubmed.ncbi.nlm.nih.gov/15769618/
- Retinal pigment epithelium: https://pubmed.ncbi.nlm.nih.gov/15987797/
- Corneal epithelial renewal: https://pubmed.ncbi.nlm.nih.gov/26310149/
- Endothelial/pericyte interactions: https://pubmed.ncbi.nlm.nih.gov/16166562/
- Intestinal stem-cell compartment: https://pubmed.ncbi.nlm.nih.gov/23870119/
- Cholangiocyte biology: https://pubmed.ncbi.nlm.nih.gov/27563020/
- Langerhans antigen presentation: https://pubmed.ncbi.nlm.nih.gov/23246038/

Device regression exercises every microscopic entry in the native function and
simulation tabs, both locales, selected-stage Agent context, fragment identity,
large-text controls, per-entry recreation and background playback suspension.
Tests use isolated fixture stores and do not send a real Provider request.

## Ideal Vessel-Segment Flow

Blood vessels, arteries, veins and coronary vessels expose a Hagen-Poiseuille
teaching model for one straight rigid circular tube. It assumes steady, fully
developed laminar flow, constant dynamic viscosity and no slip at the wall.
Pressure drop is between the ends of the segment, not a blood-pressure reading.
Controls span 0-20 mmHg, radius 0.05-0.2 mm, length 20-100 mm and viscosity
2-6 mPa s. These bounds are numerical teaching inputs, not clinical ranges.
The model is not assigned to capillaries, whole circulation or vascular cells.

The pure Kotlin model converts inputs to SI units, using conventional
`1 mmHg = 133.3224 Pa`, then calculates `Q = pi * dP * r^4 / (8 * mu * L)`.
The displayed flow uses `1 m^3/s = 60000000 mL/min`. Resistance is calculated
independently as `8 * mu * L / (pi * r^4)` and remains finite at zero pressure.
Mean speed is `Q / (pi * r^2)`, centre speed is twice the mean, and wall shear is
`dP * r / (2 * L)`. The circular radial profile is parabolic with zero wall speed.
Tests integrate that profile with annular areas, not a plane-channel average.

An original native longitudinal-section diagram varies geometry and depicts the
normalized speed profile. Diameter is enlarged and arrows are normalized to the
current centre speed; their lengths do not compare absolute speed across input
sets. Numerical speed and shear labels remain visible and accessible. Zero
pressure removes the moving-flow arrows. The radius-response curve holds the
other inputs fixed, with a labeled adaptive vertical scale and current marker.
Small positive flow retains six decimal places and radius retains three; other
existing models keep their previous display precision. There is no new animation
loop, background work or personal-record write.

Four saved controls remain isolated by entry and survive recreation. Simulation
and Research / Physiology share the same scoped state. Public Agent previews
include current inputs, outputs, assumptions and references, but not in unrelated
entries or drug/aging topics. Actual blood is pulsatile, non-Newtonian and cellular;
compliance, valves, branching and patient-specific geometry are not represented.
This increment does not estimate personal perfusion, vascular disease or treatment.

References are linked rather than copying textbook prose or figures:
- https://openstax.org/books/college-physics-2e/pages/12-4-viscosity-and-laminar-flow-poiseuilles-law
- https://ocw.mit.edu/courses/2-25-advanced-fluid-mechanics-fall-2013/1a114d602956fa0dd328155f9b45f93d_MIT2_25F13_Couet_and_Pois.pdf
- https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9

## Eye Structure And Focus

The original transparent vector cross-section depicts the position and relative
shape of the cornea, iris, lens, retina, eye wall and optic nerve. It is an
illustration, not a clinical image or full orbital dissection. Selectable
localized leaders route to the canonical cornea, lens and retina entries;
those detail cards identify the shared eye-section context. Existing layer,
pinch zoom, reset and fullscreen controls work with the scalable vector.

The eye and lens entries expose a separate, paraxial one-lens teaching model
in air. The model is deliberately restricted to a real-image domain:
object distance 0.25-6 m and equivalent whole-eye power 55-65 D. For object
distance `do` in metres and power `P` in reciprocal metres, the image distance
is `di = 1 / (P - 1 / do)`. The retinal plane is fixed at 17 mm, so the chart
displays the signed millimetre offset from that plane versus power. The focus
action rounds the exact target power to the nearest 0.01 D. An offset below
0.005 mm in magnitude is reported as at the plane to displayed precision.

The native ray view uses one axial object point, derives both rays from
the same image distance, and uses separate horizontal scales before and
after the lens. The diagram, inputs and results update in place. States
restore independently for eye and lens, including Research / Physiology.
The public Agent preview carries current inputs and results, not personal
visual measurements. None of this predicts a prescription, acuity,
refractive diagnosis or the focal power of the crystalline lens by itself.

- Anatomy reference: https://www.nei.nih.gov/eye-health-information/healthy-vision/nei-for-kids/about-eye
- Thin-lens reference: https://openstax.org/books/university-physics-volume-3/pages/2-5-the-eye

## Ear Anatomy And Hearing

An original ear-section vector shows the pinna and canal, eardrum and middle
ear, cochlea and semicircular canals. Five localized hotspots link to outer
ear, middle ear, inner ear, cochlea and the vestibular apparatus. Subpart
cards retain the whole-ear caption and highlight the selected structure.
The ear and these five subparts each have a separate four-step mechanism
in English and Chinese. Cochlear hearing is distinguished from vestibular
responses to rotation, linear acceleration and gravity; the vestibular
stages are a conceptual sequence, not consecutive events in one movement.

The ear and middle ear expose a lossless ideal transformer based on a lever
and two effective areas. The pressure ratio is `N = (Ain / Aout) * lever`.
The pressure gain is `20 * log10(N)` dB and the volume-velocity ratio is
`1 / N` under the lossless assumption. Both areas are in mm^2; their units
cancel. The controls span 35-75 mm^2, 2-5 mm^2 and lever ratio 1-1.6. The
native diagram uses a common area scale and schematic lever arms. Curve
points vary the effective eardrum area with other inputs fixed.

This is not an absolute sound level, sound-energy gain, audiogram, or
prediction of individual hearing. The model excludes frequency dependence,
cochlear load, stiffness and losses. No test tone, microphone capture, or
write to personal health records is involved. The Agent preview scopes
active settings to hearing physiology only.

- Ear anatomy: https://www.nidcd.nih.gov/health/how-do-we-hear
- Hearing and vestibular mechanisms: https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception
- Pressure-transformer equation and fuller model: https://pmc.ncbi.nlm.nih.gov/articles/PMC4570511/
- Frequency-dependent human temporal-bone measurements: https://pubmed.ncbi.nlm.nih.gov/28079680/

## Continuous Heart Function

The Function tab for the cardiovascular system, heart, chambers and valves
uses the existing painted section. Its shared five-chapter player animates
filling, atrial contraction, pressure rise, ejection and early relaxation.
Directional tracers follow ventricular inflow or outflow only during the
corresponding phase; illustrated leaflets signal open and closed valves. The
mesh narrows visibly during ejection, not during either isovolumic phase.
Colored tracers encode relative oxygen content, not actual blood color.
This lesson does not calculate cardiac output, valve pressure or transit
times. Personal measurements and the separate simulation are unaffected.

## Continuous Breathing And Gas Exchange

The Function lesson connects chest-scale airflow and diaphragm motion to a
painted alveolar close-up. The close-up depicts flowing red blood cells and
simultaneous oxygen and carbon dioxide diffusion in opposite directions.
Chapters change focus, not the underlying order of gas exchange. Arrows,
breath and vessel timing are illustrative; the fixed gas-gradient teaching
examples remain in Simulation and are not plotted as personal measurements.

## Continuous Hearing

The Function lesson uses the painted ear cutaway, hair cell and brain.
Moving pressure bands in the ear canal, motion of the eardrum and ossicles,
the traveling wave on an unrolled basilar membrane, tilting of the hair
bundle, and propagating marks on a schematic neural pathway are distinct
scenes. A simplified path to cortex shows a brainstem/relay stop; it is not
a projection of exact internal anatomy onto the lateral illustration.
No audio, microphone, frequency measurement or hearing test is involved.
The vestibular catalogue entry and the separate middle-ear simulation
retain their own behavior.

## Continuous Nephron Function

The Function lesson layers directed markers onto the painted nephron:
filtration, proximal reabsorption, water and salt transport in the loop,
distal secretion, and collecting-duct transport. Filtrate and blood are
distinct; nearby capillary paths are schematic. This view is qualitative
and independent of personal measurements and the solute-balance model.
The Function player puts the button row and timeline before the illustration
and limits canvas height in short windows so playback remains reachable.

## Continuous Digestion And Water Recovery

The meal lesson follows a bolus through swallowing, esophageal propulsion,
stomach mixing, and duodenal digestive secretions before zooming to the
painted villi. Separate paths illustrate blood uptake of sugars and amino
acids and lymphatic transport of most long-chain fats. A second lesson
shows ileocecal entry, local mixing versus propulsive contractions, water
recovery, and rectal storage. The two entry groups retain separate playback
positions; the villus geometry model and individual cell lessons are
unchanged. Neither animation estimates a transit time or nutrient intake.

## Continuous Vision And Light Adaptation

The vision Function lesson separates refraction in the painted eye,
reduced transmitter release in response to light, a representative cone
relay and optic nerve output. The brain drawing supports a schematic
route, not a precise map of the chiasm or deep structures. The rod and
cone entries have a separate light adaptation lesson with illustrative
brightness and contribution cues, not calibrated thresholds. The thin
lens and retinal circuit simulations remain independent.

## Continuous Skeletal Muscle Motion And Bone Remodeling

The muscle lesson follows a motor nerve signal to a muscle fiber, calcium
release, sliding filaments of fixed length, and tendon-driven elbow
motion. Elbow extension uses the antagonist rather than treating biceps
relaxation as a force. The illustrated joint motion is not the lever-force
simulation. The glucose uptake lesson on skeletal muscle tissue remains
unchanged.

The bone lesson follows a local bone surface from osteocyte signaling to
resorption, reversal, osteoid deposition and mineralization. The depth
and colors make these stages visible but do not estimate bone density,
timing or individual health. Muscle and bone lessons preserve separate
playheads and pass only the displayed public chapter to Agent.

## Continuous Lymph Return And Antibody Response

The lymph lesson separates filtration from a blood capillary, uptake
through the flap-like edges of initial lymphatics, alternating valves in
a collecting segment, passage through a lymph node, and return to a vein
through the thoracic duct. The painted node and duct reuse their existing
anatomic paths. The spleen is not part of this lymph drainage route.
Valve motion is qualitative and independent of the pressure model.

The antibody lesson shows one T-cell-dependent response: B-cell
recognition, help, expansion, differentiation, and release of antibodies
that bind matched antigens. Cell counts and timing are illustrative.
Existing anatomical hotspots and simulation panels remain available.

## Insulin Secretion And Multiple Function Lessons

An illustrative human beta cell shows glucose entry, reduced potassium
efflux through ATP-sensitive channels, voltage-gated calcium entry,
granule fusion, and release to a local capillary. This is distinct from
the GLUT4 uptake animation in skeletal muscle and fat. Related lesson
links connect secretion to uptake without implying that GLUT4 triggers
the beta cell. Neither lesson estimates a glucose level or medication dose.

Pancreas, skeletal muscle tissue, and the immune system can switch lessons
in place. Saved activity state separates each entry and lesson; old
single-lesson playheads restore into the default lesson. Agent receives
only the public chapter and references from the selected lesson.

## Glucagon Counter-Regulation And Evaporative Cooling

The glucagon lesson follows secretion from an alpha cell and receptor
signaling on a liver cell. The hormone and glucose are different tracers:
hepatic glycogen breakdown and transport provide glucose, not conversion
of the hormone into fuel. Pancreas, endocrine system and islets expose
separate insulin and glucagon lessons; the pancreatic digestive lesson
remains the default.

The eccrine sweat lesson reuses the anatomical duct path. It distinguishes
secretion, ductal salt recovery, liquid on skin and evaporation. A drier
and a more humid case start with equal visible sweat. The comparison is
qualitative and independent of the existing simulation; it cannot predict
core temperature, fluid loss or personal glucose.

## Neuronal Transmission, Myelin, And Thyroid Feedback

The synapse lesson distinguishes a voltage signal along the axon from
chemical signaling across the cleft. In the selected excitatory example,
calcium entry precedes vesicle fusion and transmitter release. A separate
myelin lesson compares oligodendrocytes and Schwann cells, highlights
regeneration at exposed nodes, and shows local current inside the axon
rather than a jump through extracellular space.

The thyroid lesson uses the anterior pituitary portal route for TRH and
bloodstream transport for TSH and thyroid hormones. The final stage shows
negative feedback to two upstream sites. The lessons do not compute
clinical hormone values or an absolute conduction speed. The original
endocrine pathway, potassium model, structure plates, and personal
measurement flow are unchanged.

## Epidermal Barrier And Gamete Transit

The surface-barrier lesson follows epidermal cells from the basal layer
to flattened corneocytes. An inset shows lipids released into the gaps
between cells. The water comparison holds the observation window fixed
and illustrates a relative difference rather than a measured rate. Skin
keeps sweat cooling as the other lesson; neither substitutes for a skin
assessment.

The male lesson separates formation in the seminiferous tubules, fluid
transport into the epididymis, maturation, storage, and muscular
propulsion through the vas deferens. The female lesson follows follicle
development, rupture, pickup by the separate fimbrial opening, ciliary
and muscular transport, and arrival at the ampulla. It does not equate
ovulation with fertilization or implantation. The existing germline
chromosome-count diagrams remain available independently of the
animations; neither animation predicts fertility or timing for a person.

## Sensory And Alimentary Overview Lessons

The sensory overview opens a compact named picker for visual, auditory,
vestibular, olfactory, taste, and touch lessons. The entry keeps a
separate playhead for each lesson. The alimentary overview links the
meal and colon chapters without conflating them with the lesson on
digestive glands.

The nasal cutaway distinguishes inhaled molecules from signals passing
through the cribriform plate. The taste example models sweet-responsive
type II cells, not a map of the tongue or a single mechanism for all
tastes. The touch example contrasts onset and sustained firing in a
Merkel-cell and sensory-nerve complex. The vestibular lesson separates
canal fluid lag, cupula displacement, otolith movement, and compensatory
eye rotation. These are educational paths, not personal sensitivity
measurements or clinical tests.

## Ocular Cell Lessons

The additional ocular scenes separate three processes: retinoid exchange
between rods and the retinal pigment epithelium, the AII relay into ON
and OFF pathways in the inner retina, and normal corneal surface renewal.
The rod relay distinguishes electrical coupling from glycinergic
inhibition. Corneal surface renewal shows inward migration separately
from movement through the epithelial layers. Its colored routes are
schematic and do not model injury, recovery time or corrective optics.

Retina, rod and cornea entries retain their earlier vision or light
adaptation animations as the default. The existing optics simulation and
structural plates remain separate from the new cell-function scenes.
