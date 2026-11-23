# Android #4352: iOS Lymphatic Organ Lessons

## Review Scope
- Ports Android #4352 at `108afffd1545f2ba10633e754ba907dc38495132`.
- Base is `main`; predecessor iOS #4474 is already merged. No inherited unmerged feature scope.
- iOS only. No Android/Desktop changes, version bump, IPA, personal archive writes or new observations.

## Implementation
- Nine existing organs receive independent four-stage mechanisms and matching section artwork: marrow, thymus, spleen, lymph nodes, collecting lymphatic vessels, thoracic duct, tonsils, adenoids and GALT.
- Nine original vector PDFs preserve 100 Android paths, 30 explanatory landmarks and 12 canonical anatomy links.
- Selected stages highlight the source feature; node and duct transport use eight exact source paths. Shared playback retains bounded per-entry phase, stage and speed.
- The collecting-vessel-only ideal check valve computes max(delta pressure, 0) / resistance; the signed no-valve comparison remains separate. This is synthetic teaching, not measured transport.
- Agent context includes the current feature and illustration scope only for the matching entry and physiology/simulation screen; anterior-view orientation is specific to the thoracic duct.
- Both languages include all 124 source strings, with Android apostrophe escaping removed and format placeholders adapted.
- Full graph remains 313 canonical entries, now 178 independent mechanisms; 108 dedicated microscopic pictures are unaffected.

## Verification
- `node apps/ios/tools/check-body-atlas-lymph-organs.cjs`: pinned source parity for graph, paths, features, links, stage mappings, transport routes and 248 localized values.
- `npm run check:ios`: project structure passed.
- `node apps/ios/tools/check-atlas-module-flags.cjs`: static build-setting audit passed.
- Swift grammar parsing passed for 13 changed Swift files under both conditional branches; this is not Swift type checking.
- Poppler rendered all nine PDFs; 42 feature/link anchors were nonblank. Contact sheet inspected.
- XCTest source added for flow fixtures, ownership, restoration, canonical links, route endpoints, phase bounds and context isolation. Not executed, as requested.
- Windows has no Xcode: no native compilation, simulator/device launch, VoiceOver, animation acceptance or IPA claim.

## Reproduction
The import tool requires `pdf-lib` and `xml-js` through `NODE_PATH` and reads pinned Android drawable sources from git. The parity checker also requires `xml-js`.
