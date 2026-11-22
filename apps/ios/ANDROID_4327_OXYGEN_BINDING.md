# Android #4327: Oxygen Binding and Whole-Blood Content

## Source and Independent PR Scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4327
- Source merge: `a86f52d99ee87015f39e3e4d94e303c373c61539`.
- This main-based increment provides the closed oxygen equations, ten bilingual strings, regression source and its module build variable. It does not duplicate the unmerged atlas/physiology implementation, change Android/Desktop code or versions, install a provider or generate an IPA.
- The shared native renderer, integer-backed controls, curves, restoration and public context wrapper are in https://github.com/galaxyssi/GalaxySSI/pull/4430, updated with the optional oxygen case. Atlas routing and condition collection are in https://github.com/galaxyssi/GalaxySSI/pull/4428. **The native oxygen surface requires this PR plus #4428 and #4430.** Scoped Agent actions and erythrocyte artwork remain separate increments in #4431 and #4432.

## Exact Equation Port

`GalaxySSIHealthAtlasOxygen` uses the same reciprocal Hill form as Android:

```text
S = 1 / (1 + (P50 / PO2)^2.7), with S = 0 exactly at PO2 = 0
Bound = 1.34 x (Hb / 10) x S
Dissolved = 0.0031 x PO2
Total = Bound + Dissolved
```

PO2 and P50 are mmHg, Hb is g/L, and oxygen content is mL O2 per dL of whole blood. Hb is converted to g/dL once; content uses the fraction S, not saturation percent. Invalid/nonfinite pressures, nonpositive/nonfinite P50 and negative/nonfinite Hb are rejected through the existing optional-result Swift style. The reciprocal form avoids infinity/infinity for extreme finite pressure ratios.

The wrapper is scoped only to `blood` and `cell-erythrocyte`. Controls match the source: PO2 0...150, default 100 mmHg; raw P50 150...400 / 10, default 26.8 mmHg; Hb 50...200, default 150 g/L. The horizontal axis varies PO2 and the vertical axis is saturation 0...100%. Hb changes content, not this saturation curve. The existing 121-point native parameter plot is reused, not duplicated.

The panel and public teaching context include total/bound/dissolved quantities, current inputs, fixed-exponent assumptions and both sources:

- https://pmc.ncbi.nlm.nih.gov/articles/PMC2862600/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/

Per-entry raw inputs use the existing public selection state and reset path. Animation phase/speed remain independent of the numerical calculation. A source-matching process note distinguishes qualitative stages from equilibrium output. Inactive anatomy/research context is not appended. No personal observation, pulse-ox reading, archive or transport is an input to this helper.

## Build Condition Integration

This increment contributes `GALAXYSSI_ATLAS_OXYGEN_FLAGS` in both project configurations. Companion increments contribute separate physiology/context variables. The foundation collects them into inherited `OTHER_SWIFT_FLAGS` for both app and test targets. Without a companion variable its condition is absent, so independently submitted increments do not reference missing implementation files.

The current IPA workflow replaces `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on the xcodebuild command line. Module flags therefore cannot rely on app-local literal additions to that setting. The project-level variables and separate inherited flags preserve the module conditions and also make optional integration regression code visible to the test target when its implementation dependencies exist. This is a static configuration fix; no IPA/Xcode build result is claimed.

## Verification Boundaries

- `npm run check:ios` and `git diff --check`: static project/whitespace checks.
- All ten English/Chinese resources compared with structured-parsed Android XML after Cocoa format conversion, including newline/Unicode handling.
- Swift grammar audit covers the new helper, localization/test source and shared model/atlas adapters in all eight module-condition combinations. This is not Apple SDK type checking.
- Static build-setting analysis checks Debug/Release condition composition and the current workflow's replacement setting. It does not replace an actual Xcode build-settings or binary inspection.
- Reproducible settings audit: `node apps/ios/tools/check-atlas-module-flags.cjs --foundation-ref origin/ios/android-4322-body-atlas-20261122 --physiology-ref origin/ios/android-4324-physiology-models-20261122 --context-ref origin/ios/android-4325-scoped-atlas-agent-20261122`. All eight module subsets pass for project Debug/Release, with no app/test target override hiding inheritance. After prerequisites merge the reference options can be omitted.
- `git merge-tree --write-tree` succeeds against each of #4428 through #4432. The updated foundation/physiology/context heads also pass their three pairwise merge simulations. These are static text-integration checks, not native execution; no PR is merged by this work.
- Six focused XCTest methods port half saturation, zero pressure, unit conversion, content conservation, affinity/curve bounds, invalid/extreme inputs, source links and localized limits. Two additional integration methods cover canonical ownership, integer restoration, hemoglobin-independent saturation curves, current components and both sources in the public context when the shared module is present. **Not executed**, per request.
- No XCTest suite, simulator/device run, Xcode/IPA build, clinical validation, real-provider answer or follow-up acceptance was performed on Windows. Android's device/JVM results are not reported as iOS evidence.

## Scientific Limits

This is a fixed-exponent equilibrium teaching approximation, not a complete multivariable gas-exchange model or a prediction of an individual's physiology. The source states its most reliable region is approximately 20-98% saturation; slider bounds are teaching ranges, not clinical reference intervals. pH, CO2, temperature and abnormal hemoglobins are not modeled separately. It is not a pulse-ox interpretation, oxygen-delivery estimate or treatment recommendation. This increment does not complete the entire body-explorer or Android-to-iOS backlog.
