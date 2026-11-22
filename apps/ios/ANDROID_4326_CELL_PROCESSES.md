# Android #4326: Owned Cell Processes and Interactive Stages

## Source and Independent Scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4326
- Source merge: `427b3083fb749505fe135f284124f7b4a3e4c0f3`.
- This main-based increment contains the actual cell process/plate resource pack, Chinese additions, static composition auditor and resource regression source. It does not duplicate the atlas foundation, change Android/Desktop production files or versions, install a provider or build an IPA.
- The native consumer, graph ownership validation and stage-selection helper are in https://github.com/galaxyssi/GalaxySSI/pull/4428, updated at `e3b0ecf88`. **Both PRs are required to display this increment.** Merging the resource pack alone packages its assets but leaves the legacy body page unchanged.
- The pack is independent of the organ increment in https://github.com/galaxyssi/GalaxySSI/pull/4429: it loads with or without that pack. The complete source catalogue comparison includes both. Associated numeric models and scoped Agent actions remain in https://github.com/galaxyssi/GalaxySSI/pull/4430 and https://github.com/galaxyssi/GalaxySSI/pull/4431.

## Feature Mapping

| Android change | iOS implementation |
| --- | --- |
| Thirty dedicated core-cell mechanisms | `HealthAtlasCellProcesses.dataset`: thirty exact source mechanisms and thirty explicit entry-to-mechanism assignments, preserving canonical IDs |
| Four localized stages per process | 120 stage labels and thirty titles, with the exact source OpenStax chapter for each process |
| Cell ownership invariants | The consumer requires each cell-specific mechanism ID to identify its owning cell, whose selected mechanism must equal that ID. Another cell or organ cannot reuse it. Duplicate, dangling or misassigned extensions are rejected |
| Erythrocyte illustration | Original transparent 1254 x 1254 PNG, routed only to `cell-erythrocyte` |
| Representative myelinated neuron | Original transparent 1024 x 1536 PNG, routed only to `cell-neuron`, with its source caption and aspect ratio; it is not reused for every neuron subtype |
| Native stage selection | Native labeled buttons use the validated phase-selection helper, pause playback, expose selected/accessibility identifiers and preserve rate/volume/speed/quantitative inputs; visual positions follow Android's 1-2 / 4-3 layout, with ordinal stage labels and logical VoiceOver order |
| Phase restoration | Existing bounded public per-entry state, keyed by the same cell IDs; selection changes phase only and keeps the existing serialization path |
| Bilingual text | 152 English strings in the data asset and 152 matching Chinese strings in the already registered localization table, including the two plate captions |

The thirty owned processes cover erythrocytes, selected immune cells, neurons/glia, muscle cells, skin/support cells, bone/cartilage cells, vascular endothelium, hepatocytes, pancreatic beta cells, enterocytes, spermatozoa and oocytes. Other cell subtypes intentionally retain their broader mechanisms. Counts remain 105 cell types/subtypes and one platelet fragment; this does not invent thirty additional cell types.

No new project references are needed: the assets use the registered asset catalog and the resource regression is in the existing Health theme XCTest source. The foundation's frozen-baseline tests explicitly use `includeExtensions: false`; installed extensions do not silently change those fixture expectations.

## Verification Actually Performed

- `npm run check:ios` and `git diff --check`: static checks passed.
- `node apps/ios/tools/check-body-atlas-cell-processes.cjs --base-ref origin/ios/android-4322-body-atlas-20261122 --organ-ref origin/ios/android-4323-organ-plates-20261122 --android-ref 427b3083fb749505fe135f284124f7b4a3e4c0f3`: passed. The complete composed 281-entry/50-process JSON equals Android #4326, including entry ordering and all mechanism fields. All thirty owners and relationship references resolve; both PNG blobs equal their source byte-for-byte.
- All 152 English and 152 Chinese strings compared with structured-parsed Android XML: equal. Resource keys, four-stage counts and owner-scoped artwork routes are audited.
- Original assets inspected locally; Windows image decoding confirmed dimensions and nonopaque corner alpha. These are source assets, **not screenshots of the running iOS app**.
- Swift grammar parsing covers the updated consumer, simulation and regression sources. This does not prove Apple SDK type correctness or native behavior.
- `git merge-tree --write-tree` succeeded against the current foundation (`ce7545f3a`) and each of #4429, #4430 and #4431. These are pairwise text-conflict checks, not native build or runtime evidence; no PR was merged.
- XCTest source added for packaged process/caption/image resources. Foundation regression source additionally covers rejection of a cell process assigned to another cell or organ, phase-only selection and serialization round-trip. **Not executed**, per request.
- No XCTest suite, Xcode build, simulator/device run, IPA, live-provider response, native focus/large-text/layout acceptance or image rendering certification was performed on Windows. Android's device test results are not claimed as iOS results.

The static auditor also works after merging the prerequisites, using the local frozen base and organ pack without the reference options. A resource-only branch explicitly reports the missing local foundation and does not claim a runtime validation pass.

## Scientific Boundaries

These four-step sequences are simplified qualitative teaching material, not patient observations, diagnostic imagery or numerical predictions of cell activity. The neuron image is representative, not universal anatomy. Associated whole-process equations, where available, retain their independent assumptions and do not become a validated cell-specific simulation. Personal values, consent, provider routing and transport behavior are not changed by this resource increment. Remaining subtype-specific pathways, imagery and validated models are not claimed complete.
