# Android #4420 iOS Port

Pinned source: `241177bc16b63d1b4da966c9d754144f8506de26`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4420

## Review Scope

Base remains main. Inherits OPEN formal #4509 and its documented predecessors;
none is assumed merged. Full main diff contains inherited work, not only this
feature. Incremental review base: `7bb6a7acd95fe4aa873b2e99b0a09fcdd75ef804`
(#4509 head). Only iOS files change; no Android/Desktop edits or IPA.

All four original files have pinned hashes/dispositions: simulation panel,
activity, circulation device-test reference and Android version. See
ANDROID_4420_SOURCE_INVENTORY.json and ANDROID_4420_PORT_COVERAGE.json.

## Implementation

- Add default-false mechanismFirst. Only physiology research opts in, so its
  animated mechanisms/playback precede the numerical panel. Independent
  Simulation retains the Android policy: numerical controls first except for
  gas exchange, pancreatic routes, endocrine paths, sweat and non-cell sections.
- Use complementary before/after conditions and one shared numerical invocation.
  This prevents overlapping special cases from duplicating the panel and removes
  the previous retinal exclusion that could omit its numerical model. Preserve
  the same entry-local inputs and existing lung/alveolar legacy migration.
- Mechanism views, phase/stage callbacks, timers, lifecycle/Reduce Motion pauses,
  reset actions, linked structures, sources and cardiac controls are unchanged.
  Model formulas, parameters, artwork and routes are unchanged. Research/drug/
  aging navigation and the independent detail surface retain their bindings.
- Fix a discovered restoration bound: the catalogue has 313 entries, beyond the
  original 300-entry cache limit. Accept up to max(300, current catalogue count),
  retaining the 256KB byte bound, valid-entry filtering and all parameter,
  function/artwork/metric sanitization. This does not remove other cache limits.
- Add XCTest SOURCE fixtures comparing research/default policy for every
  catalogue entry, keeping phase/speed/numerical settings, isolating a child
  entry and restoring the full selection cache. Tests were not executed.

## Source Verification And Limits

Passed four source hashes/dispositions, exclusive placement/research opt-in,
bounded restoration and inherited #4418/#4417/#4414 source checks. Exact source
comparison preserves the remaining simulation-panel and research behavior.
Portrait-cell artwork/dimension/ordering source checks also passed. Four changed
Swift files parsed without grammar errors after conditional directives were
removed. iOS project structure and whitespace checks passed.

No Swift type checking/Xcode build, Android tests, XCTest execution, native
render/order/gesture/drill-down/state acceptance, simulator/device launch or
IPA. These checks establish source wiring, not native UI parity or runtime
certification. Android verification is not iOS evidence; inherited native and
vector acceptance gaps remain.
