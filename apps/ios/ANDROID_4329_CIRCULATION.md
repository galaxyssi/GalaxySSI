# Android #4329: Interactive Circulation Diagram

Ports [Android #4329](https://github.com/galaxyssi/GalaxySSI/pull/4329),
frozen merge `db61b8683427bcb368197df92655e3234da8ba98`.
One formal main-based iOS PR; Android, Desktop and build versions are unchanged.

## Mapping

- Native SwiftUI lung, heart and body-tissue nodes replace the generic stage grid for the same eleven cardiovascular entry IDs.
- Four directed legs preserve the systemic-vein, pulmonary-artery, pulmonary-vein and systemic-artery sequence; incoming/outgoing heart ports are separated.
- Original bundled lungs/heart/body images are reused. Day/night route colors match Android exactly.
- Native stage buttons pause playback and change only phase. Existing sliders, reset, reduced-motion handling, scene pause and per-entry restoration remain authoritative.
- Simulation and Physiology research share the same simulation binding. Lung/heart navigation pauses playback and retains the parent entry's inputs, phase and research selection.
- Only heart/cardio show cardiac-output teaching values. No measured blood transit, pressure, exchange, coronary branches or patient prediction is introduced.
- Public Agent context includes the scientific scope, circulation path, anatomical source and selected stage only on Simulation/Physiology with a matching entry snapshot. Values never uses this public route.
- English and Chinese circuit labels/scope/path plus all four cardiovascular stage names match Android resources.

## Verification Boundaries

Static project/asset registration, source syntax, localization parity and Git merge simulations are checked.
XCTest regression source covers supported IDs, nonfinite/clamped phase, four-leg oxygenation, and prompt scope.
No XCTest, Xcode compilation, simulator rendering, live Provider response, IPA or device acceptance was run on Windows.
Responsive native labels and anchor-based paths are implemented, but visual parity and large-font rendering still require macOS/device verification.
