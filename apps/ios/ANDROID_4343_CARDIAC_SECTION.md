# iOS parity: Android #4343 cardiac anatomy and valve cycle

Base: main. Android source: #4343, merge fcd784640f7e01f12767fdedfb4cc75be09f9d74.

## Scope

- Add all ten canonical cardiac structures, eleven dedicated four-stage
  mechanisms and the exact chamber/tissue/cardiomyocyte graph connections.
- Preserve the exterior view and add a selectable internal section with six
  chamber/outlet landmarks. Use a separate four-landmark valve view.
- Convert all 19 original section paths to a transparent vector-preserving PDF.
- Synchronize visible and accessible valve states with the existing phase,
  playback, reset, reduced-motion and preview-pause controls. Scope the Agent
  explanation to the selected valve and current simulation/physiology phase.
- Add independently restored ejected/residual volume inputs for ventricles,
  right-ventricle and left-ventricle only. Show EDV and synthetic EF with the
  shared response curve. Never write simulated values to personal records.
- Preserve the selected artwork and its caption/reference in the public preview.
- Import all 103 English/Chinese strings per language.

## Verification

- iOS project structure and changed-source Swift grammar checks.
- Static Android/iOS catalogue delta and localized resource comparison.
- Full resource composition equals Android #4343: 311 entries / 158 mechanisms.
- PDF rendered using Poppler and visually inspected; this is asset review,
  not a native iOS screenshot or device acceptance.
- Added XCTest source for all sixteen valve/stage states, ejection fixtures,
  bounds, restoration, view routing and active/inactive public-context isolation.
  XCTest was not executed.
- No Xcode compilation, simulator/device run or IPA is claimed on Windows.

This is a formal main-based iOS-only PR. The preceding tissue feature is not
duplicated in its diff.
