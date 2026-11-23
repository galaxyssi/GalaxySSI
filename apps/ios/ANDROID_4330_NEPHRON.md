# Android #4330: Nephron Exploration

Source: [Android #4330](https://github.com/galaxyssi/GalaxySSI/pull/4330),
merge `8ecbef31cfcc6c4fb8fdf9b9aeea006cc56562d9`.
One independent formal iOS PR based on main; no Android/Desktop or version changes.

## Changes

- Original nephron PNG, six full-bitmap normalized markers and eight canonical structure routes.
- Four new structures, nine revised entries and seven owned renal/urothelial cell mechanisms, delivered as a validated additive data set rather than replacing the base catalogue.
- Complete composition preserves Android order and equals 285 entries / 57 mechanisms.
- Solute balance uses one guarded equation for displayed result, curve, reabsorbed companion and four directed transfers. Only synthetic bounded controls are used, not health records, urine volume or eGFR.
- Existing renal model now also maps proximal tubule, nephron loop and distal tubule, without mapping podocytes or mesangial cells.
- Native transfer labels remain readable independently of arrow color/width; zero transfers dim the arrow.
- Both languages include all 60 renal strings; public quantitative context includes scope and each directed transfer.

## Shared Integration

The existing atlas artwork supports native numbered markers, wrapped accessible labels, zoom/fullscreen and per-entry selection restoration. iOS uses scrollable native label rows rather than Android's constrained-height label-column packing.
The generic plate reference and illustration Agent-preview integration is supplied by the existing foundation update in [#4428](https://github.com/galaxyssi/GalaxySSI/pull/4428) and typed context update in [#4431](https://github.com/galaxyssi/GalaxySSI/pull/4431); it is not duplicated here. This PR includes a compatible optional source field for its new plate and remains buildable against main. These references describe functional integration dependencies, not a stacked PR base.

## Verification

Static resource audit compares the complete composed graph, PNG bytes/dimensions, marker positions, routes and source with the frozen Android merge.
Project/source registration and Swift grammar are checked. XCTest source covers conservation, invalid numbers, model mapping, canonical structure IDs and owned cell mechanisms.
No XCTest, Xcode build, simulator, IPA or physical-device acceptance is claimed on Windows. Visual parity/large-font navigation still require native verification.
