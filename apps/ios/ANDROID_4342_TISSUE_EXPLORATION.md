# iOS parity: Android #4342 tissue exploration

Base: main. Android source: #4342, merge 1ab5e34eb81502f725d0070c47482677ea5ce8fd.

## Scope

- Add all 14 tissue entries and their exclusive four-step mechanisms, preserving
  53 distinct organ/structure locations and 26 distinct canonical cell examples.
- Add a searchable Organ/Tissue catalogue and an Organ/Tissue/Cell selector
  inside organ structure details. Preserve the selected catalogue and per-organ
  layer through navigation and scene-state restoration.
- Import all 14 original vector schematics (546 paths) as transparent,
  vector-preserving PDF assets with all 17 cell hotspots. Reuse existing
  labels, layers, fullscreen and drilldown rather than duplicating those controls.
- Validate explicit organ locations, shared systems, cell examples and exclusive
  tissue mechanism ownership. Keep legacy catalogue records decodable.
- Include only the selected tissue's public locations and cell examples in the
  Agent preview; keep the selected simulation step in its existing scoped flow.
  Exclude Values in both current and legacy prompt paths. Add no personal
  measurement inference or clinical simulator.
- Import all 119 English/Chinese tissue strings per language and update the
  four-part category/structure/tissue/cell count format.

## Verification

- iOS structure, changed-source Swift grammar and whitespace checks passed.
- 238 localized tissue strings match Android XML.
- Static resource audit confirms 14 exact entries/mechanisms, 53 locations,
  26 cells, 14 vector assets and 17 valid cell hotspots.
- All 14 PDFs were rendered with Poppler and visually reviewed together.
  This verifies assets, not native iOS layout or device behavior.
- Added XCTest source for graph validation, layer persistence, legacy defaults,
  search, source localization and public-context isolation; not executed.
- No Xcode compilation, simulator/device acceptance or IPA is claimed on Windows.

This formal main-based PR changes iOS only. The preceding ear implementation
is not copied into its diff.
