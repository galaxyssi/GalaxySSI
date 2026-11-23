# Android #4331: Alveolar Gas Exchange

Source: [Android #4331](https://github.com/galaxyssi/GalaxySSI/pull/4331),
merge `c3b829446f44109b585b55a37a13e1d683d96919`.
Independent formal main-based iOS increment, not a replacement for earlier atlas PRs.

## Mapping

- Original alveolus image, three canonical routes/markers, respiratory membrane and pulmonary capillary entries.
- Incremental respiratory graph and owned cell mechanisms. Full composition equals Android's 287 entries / 63 mechanisms.
- Club-cell research retains its explicit PubMed article source. Mechanism references accept only HTTPS numeric PubMed article URLs, not arbitrary external URLs.
- Fixed O2 104/40 and CO2 40/45 mmHg examples with simultaneous opposing arrows, native structure targets and four selectable teaching stages.
- Simulation and Physiology share per-entry phase/input bindings; navigating away pauses playback.
- Ventilation controls follow the exchange diagram; partial-pressure examples are not recomputed from ventilation or personal observations.
- Public physiology context contains scope, both fixed gradient summaries and source only for a matching entry snapshot. Values remains excluded.
- English/Chinese resources and source labels mirror Android. Respiratory membrane/capillaries map only to existing oxygen-saturation observations, without inventing a reading.

## Verification

Static graph, PNG, route and marker parity is checked by the resource audit. Project registration, source grammar, localization and Git merge compatibility are checked separately.
XCTest source covers gas direction/bounds, matching prompt scope, metrics and restrictive PubMed references.
No XCTest, Xcode compilation, IPA, simulator/device rendering or live Provider acceptance is claimed on Windows.
