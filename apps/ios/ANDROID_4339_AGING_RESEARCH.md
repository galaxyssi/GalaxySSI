# iOS parity: Android #4339 aging research

Base: main. Android source: #4339, merge 4c1e88270a51f7f97c079f314167790f5178f05f.

## Scope

- Replace the four generic aging paragraphs with all 12 selectable 2023
  Hallmarks of Aging topics, each with four conceptual stages, a localized
  explanation and canonical anatomy drilldown.
- Preserve topic and stage independently for each anatomy entry through
  navigation, tab changes and serialized scene-state restoration. Changing
  the topic resets its stage. Invalid saved steps fall back to entry defaults.
- Include the telomere and blood T-cell observational studies only for their
  corresponding active themes, including sample sizes, correlations and limits.
- Put only the selected topic, stage and relevant study into the public
  Agent preview. Do not add aging context to other tabs or personal values.
- Import 84 Android strings/stages per language. Keep physiology, drug
  inputs and personal health records separate.

## Verification

- iOS project structure and changed-source Swift grammar checks passed.
- 168 English/Chinese localization entries match Android XML exactly.
- All 12 example IDs exist in the bundled base catalogue and extension packs.
- git diff --check passed.
- Added XCTest source for topic mappings, stage bounds, per-entry persistence,
  malformed-state fallback and active/inactive preview isolation; not executed.
- No Xcode compilation, simulator/device acceptance or IPA is claimed on Windows.

This is a formal standalone main-based PR for Android #4339. The vessel-flow
implementation from #4459 is not duplicated in this diff.
