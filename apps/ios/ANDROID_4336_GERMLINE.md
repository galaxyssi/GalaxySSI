# Android #4336: Reproductive Cell Mechanisms and Germline Counts

Ports [Android #4336](https://github.com/galaxyssi/GalaxySSI/pull/4336),
merge `94154bdf32590ff7909469aeac2767c521138162`.
Independent formal main-based iOS PR; Android/Desktop and versions remain unchanged.

- Twelve owned reproductive-cell processes and revised male/female/sperm stages arrive as a validated bundled delta.
- Actual iOS pack composition matches the Android 287-entry / 75-mechanism graph, without replacing the frozen baseline.
- Four supported germline entries display stage-end chromosome/DNA counts, n/C state and lineage/paternal/maternal/combined target.
- A few native symbols indicate duplication only, not actual chromosome number or a karyotype. The oocyte sequence combines both parents only at its final stage.
- Playback controls precede the count diagram; stage buttons, slider and per-entry restoration share the existing phase state. Timing, scope and source remain visible.
- Public Simulation/Physiology preview derives counts from the matching current entry/stage. Other topics, foreign entries, Values and whole-body flows do not append germline counts.
- Synthetic teaching content never enters health records or creates genetic/fertility predictions.

Static pack composition, graph ownership, Android XML parity, source grammar, project registration and Git merge checks are performed.
XCTest source covers every supported stage, invalid counts, catalogue/selection restoration and preview isolation.
No XCTest, Xcode compilation, native screenshots, IPA or physical-device acceptance is claimed on Windows.
