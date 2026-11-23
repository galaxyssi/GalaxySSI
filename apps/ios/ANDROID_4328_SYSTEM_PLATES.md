# Android #4328: System Illustration Plates

## Scope

Ports [Android #4328](https://github.com/galaxyssi/GalaxySSI/pull/4328), merge
`dd6e7c26e3d89736ee65a05dab45223c0db2538e`, as one independent, formal main-based iOS PR.
Only iOS resources, localization, resource regression source and this mapping are changed.

- Three original, unmodified transparent Android PNGs: urinary organs, digestive tract and pancreas.
- Same full-bitmap normalized marker positions, canonical entry IDs, captions and OpenStax references.
- Ureters route to urinary organs; kidney regions retain the separate coronal kidney view.
- Pancreas art routes only pancreas, pancreatic duct and duodenum, not microscopic islets or acinar cells.
- Chinese captions preserve the schematic urethral-length limitation, omitted digestive glands and exposed pancreatic duct.

## Integration

The optional `HealthAtlasSystemPlates` data set uses the validated loader in foundation
[#4428](https://github.com/galaxyssi/GalaxySSI/pull/4428), updated at `da25f5d31`.
The shared atlas UI supplies native clickable labels, saved selection/back navigation and fullscreen.
Structure/Function show the selected plate's reference; public Ask previews include its caption,
schematic-art limitation and optional source through [#4431](https://github.com/galaxyssi/GalaxySSI/pull/4431)
at `86366bee6`. Personal Values does not use this public context.
Those executable changes are not duplicated here. This resource-only PR builds independently of
unmerged atlas Swift types, but its visible atlas behavior requires the foundation.

## Verification

The static audit compares PNG bytes, dimensions, marker lists, routing and source URLs with the
frozen Android source. XCTest source checks compiled asset availability/aspect ratio and target exclusions.
Static checks and Git merge simulations are not Xcode compilation or simulator/device acceptance.
No XCTest, IPA build or device test was run on Windows.
