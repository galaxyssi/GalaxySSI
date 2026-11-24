# Android #4385 iOS Port Status

This is an in-progress implementation, not a completed parity claim or release.

## Source And Dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4385
- Source merge: `a81aa85a1c81e41ff19a032eabea1eddcd2371dc`
- Inventory: `ANDROID_4385_SOURCE_INVENTORY.json`, 93 pinned files.
- Branch starts at `ba009094137225e74b16cebbb7d434ccd74fd24d` from iOS #4491.
- #4491 was open when this branch was created. Before publishing a formal
  `main`-based PR, recheck its merge status and the actual main-to-head diff.
- No #4385 PR has been published. Do not publish partial renderer coverage.

## Implemented In This Branch

- Separate `AtlasRegional.strings`: 431 changed/added resources per language,
  English and Simplified Chinese, with identical keys and no inherited translations.
- Latest table takes precedence over older atlas resources without rewriting the
  frozen #4384 source resources.
- Calf-pump teaching model for soleus and gastrocnemius: original ranges/defaults,
  rate axis, net-stroke formula, result/companion, references, accessibility and
  controls-before-chart placement through the existing material-response panel.
- Chamber, valves, forward-flow and returning-flow diagram; reversed horizontal
  arrowheads preserve the original positive-direction diagrams.
- Ligament-guidance first chapter now crossfades ACL/PCL footprint focus.
- Regional catalogue snapshot evaluated from original Kotlin declarations:
  114 courses, 544 chapters, 261 references and 289 owner routes. It is not yet
  activated by the runtime loader, to avoid exposing unfinished course renderers.
- Dedicated ankle-mortise renderer: five scenes, nine source paths/80 commands,
  smooth easing, talar rotation and exaggerated syndesmosis displacement.
- Dedicated scrotal-heat renderer: three scenes, eleven source paths/58 commands,
  mirrored compartments, open superior tunica attachment, vessel gradients,
  counter-directed arc-length tracers and separate heat-transfer arrows.
- Both new renderers have Xcode source registration but remain unreachable until
  the regional catalogue and complete renderer coverage are activated together.

## Remaining Before Publication

- Eleven courses: vulvar protection, accessory-gland routing, uterocervical
  continuity, penile urinary route, skull protection, vertebral motion, clitoral
  sensory path, vestibular-gland secretion, tenocyte tendon matrix, pectoral
  horizontal adduction and latissimus extension/adduction.
- New/modified structure plates, vector resource revisions and their owner/view
  selectors, features, links, sources and captions.
- Runtime catalogue activation, revision validation and complete renderer routing.
- Review pineal caching adaptation: Android changed VectorDrawable raster caching;
  current iOS implementation uses a PDF asset and must not gain redundant Android
  bitmap behavior without platform-specific justification.
- Full per-file source coverage audit and formal non-draft `main` PR.

## Verification Boundary

Source-only checks passed for the calf-pump source/formula/axis/diagram, 81,406
analytic integer-grid combinations, ankle paths/scene contracts, scrotal paths and
tracer controls, bilingual delta regeneration, preserved #4384 catalogue extraction
and material-response contracts. Swift grammar parsing passed on the edited files
in both preprocessor branches. Project structure and eight module-setting subset
checks passed. These checks do not compile or run Swift or Android scenes.

No XCTest, Xcode build, IPA, simulator/device execution, VoiceOver acceptance or
pixel verification has been performed. Windows cannot supply native iOS acceptance.
