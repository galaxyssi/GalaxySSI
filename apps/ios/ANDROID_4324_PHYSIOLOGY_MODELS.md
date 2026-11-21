# Android #4324: Interactive Physiology Teaching Models

## Source and PR Boundaries

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4324
- Source merge: `dc043ab5d0b96a2796f328a3325ecf33ccdcdc23`.
- This branch is based on `main`, not on an unmerged feature branch. It adds the model implementation, native controls/chart, bilingual text, regression source and Debug/Release build condition. No Android/Desktop production files or version changes are included.
- Native atlas routing, bounded public selection persistence and public Agent confirmation are in https://github.com/galaxyssi/GalaxySSI/pull/4428. This increment contributes `GALAXYSSI_ATLAS_PHYSIOLOGY_FLAGS` in both app configurations; the foundation collects it through inherited `OTHER_SWIFT_FLAGS`. This avoids the existing IPA workflow's command-line replacement of `SWIFT_ACTIVE_COMPILATION_CONDITIONS` erasing the module condition. The foundation itself does not enable this module.
- The complete new model surfaces require this PR **and #4428**. This branch intentionally does not duplicate the atlas foundation. Its model/view/text sources do not reference an unmerged atlas type. The foundation retains its original model UI when the condition is absent. The #4323 organ artwork increment is separate in https://github.com/galaxyssi/GalaxySSI/pull/4429.

## Exact Model Port

| Model | Inputs, scale and defaults | Formula and units |
| --- | --- | --- |
| Alveolar ventilation | Rate 6...30, default 12/min; tidal volume 200...900, default 500 mL; dead space 0...200, default 150 mL | Rate x (tidal - dead space) / 1000, L/min; companion total minute ventilation = rate x tidal / 1000 |
| Solute excretion | Filtered load 0...200, default 100 mg/min; reabsorption 0...100, default 90%; secretion 0...100, default 10 mg/min | Filtered x (1 - fraction/100) + secretion, mg/min; companion reabsorbed amount = filtered x fraction/100 |
| Potassium equilibrium potential | Outside raw 10...200 / 10, default 4 mmol/L; inside 50...200, default 140 mmol/L | (8.31446261815324 x 310.15 / 96485.33212) x 1000 x (ln(outside) - ln(inside)), mV; companion concentration ratio |

The source-linked parameter-response curves use the same equations as their result labels, not a separate approximation or a time series. The varied axes are tidal volume, reabsorbed fraction and extracellular potassium. Other parameters remain fixed. There are 121 curve samples, a selected-input marker, source-matching ordinate bounds (0...27, 0...300, -150...0), localized ticks and accessible chart output/input descriptions. The plot reserves marker margins to keep endpoint markers visible.

The separate Android #4327 increment supplies a closed oxygen helper and ten strings. Its optional `GALAXYSSI_ATLAS_OXYGEN` condition adds the two-entry oxygen case through this shared renderer/restoration/context path. Without that module the original three cases remain unchanged. The wrapper exposes component quantities and multiple sources only when the corresponding implementation is present; no oxygen formula is duplicated here. The new process note distinguishes qualitative stages from equilibrium calculations without coupling animation timing to numerical outputs.

Assignment matches the source's **17 canonical IDs only**:

- Ventilation: respiratory, lungs, alveoli.
- Renal: urinary, kidneys, nephron, renal-tubules, collecting-ducts, cell-proximal-tubular-cell, cell-distal-tubular-cell, cell-collecting-duct-principal-cell, cell-collecting-duct-intercalated-cell.
- Potassium: nervous, brain, spinal-cord, cell-neuron, cell-olfactory-receptor-neuron.

Related structures do not inherit a quantitative model automatically. In particular, renal cortex/pelvis, liver/hepatocytes and type-II pneumocytes are not added to the allowlist.

## State, Interaction and Disclosure

The native panel has bounded integer-backed sliders with physical-unit labels and a reset action. Invalid raw counts, indices and ranges are rejected, not silently clamped into a different teaching state. Nonfinite/out-of-axis curve arguments and nonpositive/nonfinite Nernst inputs are rejected. Natural-log differences avoid forming an underflow-prone concentration ratio inside the potential calculation.

The foundation passes a per-entry optional integer array to both Simulation and Research / Physiology. Existing bounded public SceneStorage handles it; no readings or health archive are serialized into it. Valid old lungs/respiratory rate and tidal-volume teaching inputs migrate with default 150 mL dead space. A valid saved new model takes precedence. Other entries do not receive that legacy migration. The sequence reset resets both model and playback; the model reset changes only its quantitative parameters.

The public Agent preview includes the selected model's physical inputs, current result, companion quantity, assumptions, equation and source only from Simulation or Research / Physiology. Other tabs do not append that model context. The existing confirmation, new conversation and one-use handoff remain in the foundation. Personal record review/disclosure remains a separate route. These model files have no Health repository or network transport dependency.

Twenty-one model strings and three shared labels are ported exactly from the Android XML, with Cocoa format placeholders. English follows the existing iOS fallback-localizer pattern; Chinese is in the already registered `zh-Hans.lproj/Localizable.strings`. No Chinese text is placed in Swift/test source.

## Verification Actually Performed

- `npm run check:ios`: passed static project structure checks, including the new registered source/test files.
- Static comparison of all 24 English/Chinese resources against structured-parsed Android XML: passed. Debug and Release contain the model build condition and all four new Swift files have source registrations.
- Swift grammar parsing: new model, panel, text and XCTest source pass. The five foundation integration files were also parsed in both feature-condition states. This is **not Apple SDK type checking**.
- `git diff --check`: passed.
- Eight focused XCTest methods added for dimensions, conservation, natural log/Kelvin/millivolts, bounded monotonic response curves, invalid state rejection, the 17-entry allowlist, restoration/migration and public context. **Not executed**, per request.
- No XCTest/test suite, Xcode build, simulator/device run, IPA generation, native layout certification or real-provider Agent acceptance was performed on Windows. Build flags/conditional branches and Git merge simulations are static integration evidence, not proof of native execution.

## Scientific Limits

These are synthetic teaching identities, not personal physiology predictions, reference intervals, diagnoses or treatment recommendations. Ventilation does not estimate blood oxygen/carbon dioxide or a ventilator setting. Renal mass balance is an aggregate unspecified-solute model, not GFR/eGFR, urine volume, a drug dose or an individual cell's isolated function. Potassium assumes an ideal single-ion membrane at 37 degrees Celsius and concentration-as-activity; other ions, pumps, changing permeabilities and action potentials are excluded. Actual medical use or diagnostic validation is not claimed.
