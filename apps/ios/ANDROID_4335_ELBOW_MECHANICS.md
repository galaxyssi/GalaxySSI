# Android #4335: Static Elbow Mechanics

Ports [Android #4335](https://github.com/galaxyssi/GalaxySSI/pull/4335),
merge `97a6aa695e98a8c02b5b98171562c946c86a7553`.
One formal main-based iOS PR, with no Android/Desktop or version changes.

- Maps only skeletal, muscle, biceps, humerus, radius and ulna to the elbow teaching model.
- Same bounded controls: 0-10 kg external mass, 20-50 cm load distance and 20-60 mm perpendicular muscle arm.
- Uses fixed forearm mass 2.5 kg, centre 0.16 m and gravity 9.8 m/s². All distances are converted to metres before computing opposing moments and joint reaction.
- Reuses shared synthetic input restoration, sliders, reset, numerical curve and public physiology context; no health measurement is written.
- Native horizontal-forearm diagram shows E/B/A/L force directions, not magnitude. Zero external load becomes a dot rather than a force arrow. Separate native labels retain readable force/torque values.
- Curve maximum follows the selected lever arms and is rounded up to 100 N, bounded by the source model's 2700 N maximum.
- Bilingual assumptions/formula/scope and OpenStax source make explicit that these are not safe lifting limits, patient strength, injury prediction or rehabilitation guidance.

## Verification

Static project registration, Swift syntax, Android XML parity and Git merge compatibility are checked.
Added XCTest source covers the unrounded 470.4 N / 406.7 N / 18.816 N·m fixture, force/moment balance across controls, invalid values and bounded mapping/restoration.
Existing shared context regression source covers synthetic values and scientific sources.
No XCTest, Xcode build, simulator rendering, IPA or device acceptance is claimed on Windows.
