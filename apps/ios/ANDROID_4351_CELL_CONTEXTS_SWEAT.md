# Android #4351: complete cell artwork, sweat transport and evaporation

Ports Android merge `3db9c86a0fdb74f52ffbba29dd87c652dddb6587` to iOS 15+.

## Scope
- Import the remaining 21 dedicated cell illustrations and eccrine sweat gland/hair follicle sections as vector-preserving PDFs (168 original paths), with all 46 bilingual local explanations and two direct cell links.
- Complete distinct artwork ownership for all 107 catalogued cells and the separately classified platelet fragment. Add a final runtime check for one resolvable, uniquely named, owner-matched illustration per microscopic entry. This does not claim complete organ-specific artwork or quantitative models for every entry.
- Replace the generic sweat-gland and hair-follicle mechanisms with the exact dedicated four-stage skin mechanisms; no catalogue entries are added or removed.
- Add the qualitative sweat walkthrough over the original gland section. Use the exact Android duct geometry and native SwiftUI path trimming for length-based transport, then show surface liquid and fading evaporation bubbles. Phase and controls come from the existing playback system, including reduced-motion, foreground/preview suspension, reset and restoration. Animation speed is not clinical timing.
- Add the hair-cycle limitations without inventing a quantitative growth forecast.
- Assign latent-heat transfer only to `sweat-glands`: synthetic surface delivery 0...20 g/min in 0.1 increments (default 6), evaporation 0...100% (default 50), evaporated mass = delivered mass * fraction / 100, watts = evaporated g/min * 2426 J/g / 60. Zero evaporated mass produces zero latent-heat transfer.
- Integrate parameters, curve, localized outputs, reset, saved synthetic inputs and sources, placing the quantitative panel below the sweat walkthrough. No simulated outputs are saved as health observations.
- Scope sweat/hair teaching context to matching active simulation/physiology state; keep personal Values and unrelated owners excluded.
- Add only four exact PubMed plate references used by this port. Import all 116 strings per language with Foundation format adaptation. Preserve GalaxySSI branding/app version and Android/Desktop implementations.

## Integration
Prerequisite #4473 has merged to `main` as `667e689f41790f53b37838ea7b67121f6d0f254c`. This port reuses its sensory-cell work rather than copying it into new implementations. Base is `main`; this is a formal, non-draft PR.

## Verification performed
- `node apps/ios/tools/check-body-atlas-cell-contexts.cjs`: passed; exact source/caption/anchor comparison, all 108 distinct microscopic pictures, exact sweat duct operations, and full static graph equality with Android #4351 (313 entries / 169 mechanisms).
- Exact Android XML localization comparison: 232 strings passed.
- All 23 PDFs rendered and contact sheet inspected; all 48 feature/navigation anchors land on rendered artwork.
- `npm run check:ios`: passed (project structure only).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. Neither is Swift type checking.
- Added XCTest source for latent-heat fixtures/conservation/bounds/ownership, transport/surface phase boundaries, complete microscopic illustration ownership, context section navigation, restored stages/inputs and owner/screen isolation. XCTest was not executed, per request.

No Xcode compilation, simulator/device rendering or motion, VoiceOver acceptance, or IPA is claimed on this Windows host.
