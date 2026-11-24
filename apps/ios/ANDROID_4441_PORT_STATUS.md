# Android #4441: cellular mechanism closeups

## Exact source scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4441
- Merge: `94d3e3a33be621a5ae17c62c7082a6ea912bdfd2`.
- Incremental iOS base: `df3ccec2e062e2623954104d7a773a74beaca360`, PR #4517.
- Twelve original changed files: three production Kotlin, two test references, six XML resource files, one Android version-only change. Each hash and disposition appears in the source inventory and coverage JSON.

## Native implementation

- Muscle sliding chapter: move the constant-length filament overview above a clipped single-head cross-bridge closeup. Four source phases bind, pull, detach after ATP binding, and recover after ATP hydrolysis. Preserve 80-unit actin, 122-unit myosin, original sarcomere shortening and all other muscle/bone chapters. Pose geometry shares the source eased local quarter-phase and continuous head positions.
- Intestinal soluble-nutrient chapter: retain villus/blood flow, replace the old generic enterocyte inset only in this chapter with brush-border SGLT1, basal GLUT2 and sodium-potassium pump. Two original quadratic/line tracks distinguish glucose and sodium; opposing potassium particles enter through the pump. Keep lipid packaging, lymph transport and other chapters unchanged.
- Beta-cell potassium chapter: keep the original gate and particles, and add partial KATP-opening and delayed relative-depolarization curves sampled from zero to the current local chapter time. Calcium-entry and later secretion chapters remain unchanged. All values are qualitative teaching illustrations, not clinical measurements.
- Resources: eleven exact translated English/Chinese pairs, plus four original `translatable="false"` scientific names shared in both locale tables. Fifteen entries per table is NOT fifteen translated pairs. Importer reads the XML attributes explicitly and still rejects unapproved bilingual key mismatches. No invented translations or implicit fallback for these names.
- Three separate drawing files and existing native helpers; no replacement of lesson metadata, scene/menu, selection restoration, metrics, Agent handoff or numerical kernels.

## Verification limits

Source/resource contracts, changed Swift grammar parsing, project registration and whitespace checks only. Added Swift fixture sources cover bridge phase/pose boundaries, constant filament lengths, delayed monotonic potential, channel closure and transporter route endpoints/interior samples. Fixtures have NOT been executed.

Windows has no Xcode. No Swift type checking, XCTest, simulator/device run, in-frame caption or moving-pixel acceptance, screenshot, VoiceOver/gesture certification, or IPA. Android's device test refactor and JVM assertions are source references only, not iOS execution evidence.

## Review dependency

Formal PR base is `main`; this branch cumulatively contains preceding unmerged iOS work through #4517. Review this port with the exact incremental base above. The full main diff is NOT an independent #4441 port. Integrate predecessors in order or reconstruct an integration branch deliberately. No all-PR completion or native acceptance claim.
