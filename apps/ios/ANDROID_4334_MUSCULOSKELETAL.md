# Android #4334: Anterior and Posterior Musculoskeletal Views

Ports [Android #4334](https://github.com/galaxyssi/GalaxySSI/pull/4334),
merge `80d46ca59dd3db25e3e7d266c70f082232f4788b`.
Independent formal main-based iOS PR; Android/Desktop and version numbers are unchanged.

- Four original PNGs: skeleton front/back and superficial muscle front/back.
- The same 28 visible structure hotspots and two trusted OpenStax anatomical references.
- System owners offer both views. A structure offers only plates where its own hotspot is visible; microscopic cells never inherit a system plate.
- Native segmented view selector works inline/fullscreen. View changes reset zoom; existing labels, leaders and canonical navigation remain shared.
- Optional per-entry view keys survive navigation/restoration. Invalid or mismatched keys fall back to the first applicable view without corrupting other state.
- Caption, reference and public Agent illustration context use the actual selected view rather than a default front image.
- Six English/Chinese labels retain the posterior-muscle heel-tendon limitation.

Static source/PNG/marker/reference, XML parity, project/grammar and Git merge checks are performed.
XCTest source covers view eligibility, fallback, posterior restoration and selected-view public context.
No XCTest, Xcode compilation, simulator screenshots, IPA or physical-device acceptance is claimed on Windows.
