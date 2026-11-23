# Android #4332: System Overviews and Readable Labels

Source: [Android #4332](https://github.com/galaxyssi/GalaxySSI/pull/4332),
merge `9401329c48ea31a4c3e06e7e48b1e73ca5433eff`.
One independent formal main-based iOS PR; Android/Desktop and versions are unchanged.

- Six original transparent composite PNGs: sensory, respiratory, digestive accessory organs, endocrine, immune and skin.
- Same 32 explicit routes, 30 full-bitmap normalized markers, OpenStax references and bilingual schematic limitations.
- System overviews are fallback artwork only. Dedicated organ/cell plates retain precedence.
- Native multiline labels replace the duplicate numbered list, expand with Dynamic Type and remain selectable in inline/fullscreen views.
- Image, marker dots, leaders and labels share one UIScrollView zoom coordinate space. Pan/zoom, reset and per-entry restoration remain native.
- Layout-time visibility routing avoids other target markers. Overlapping endpoints omit an ambiguous leader; layout results are cached rather than recalculated during zoom animation.
- iOS uses vertically growing scroll content and a wider accessibility label column rather than Android's constrained-height packing loop. This preserves readable labels without clipping.

Generic source links and public illustration preview rely on the separately submitted repair [#4451](https://github.com/galaxyssi/GalaxySSI/pull/4451), not duplicated here.

Static PNG/marker/routing/source audits, project registration and Swift grammar checks are performed.
Regression XCTest source covers deterministic route geometry, overlap/invalid inputs and dedicated-plate precedence.
No XCTest execution, Xcode compilation, simulator screenshots or physical-device/large-font acceptance is claimed on Windows.
