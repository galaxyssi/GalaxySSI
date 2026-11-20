# Android Body Atlas

The public teaching catalogue contains 14 navigation categories, 158 canonical
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

Cardiac output and minute ventilation are fixed-input teaching equations.
Other sequences are qualitative, not validated quantitative patient models.
No organ score, biological age, drug dose or treatment outcome is inferred.

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

The native catalogue and research surface are not the complete virtual-human
model shown in the supplied design references. Completion requires more than
having a working generic panel for every catalogue entry:

- Extend the anatomical illustrations and selectable structures beyond the
  whole-body, heart and beta-cell views. Each image must depict its named entity;
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

Specialized artwork for the rest of the catalogue and quantitative research
models are separate work. An unrelated illustration must not be relabeled as a
different organ or cell.

Category icons are Lucide 1.72.0 paths converted into Android VectorDrawables.
SVG arcs are normalized to cubic paths with svgpath 2.6.0 to avoid Android's
incompatible parsing of compressed SVG arc flags. This is an authoring-time
conversion, not an application dependency.
The packaged `licenses/body-atlas-lucide.txt` retains the ISC and inherited
Feather notices. Icons are local assets and require no runtime network access.
