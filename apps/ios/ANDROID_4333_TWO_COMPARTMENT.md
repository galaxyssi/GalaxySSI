# Android #4333: Two-Compartment Distribution

Ports [Android #4333](https://github.com/galaxyssi/GalaxySSI/pull/4333),
merge `db61b2f0e1106624ba77b90f696e2432bce01c80`.
Independent formal main-based iOS PR; Android/Desktop and version numbers are unchanged.

- Keeps one-compartment elimination and adds a separate two-compartment mode to drug research.
- Uses the same normalized 100% central bolus, bounded integer rate controls and quarter-hour elapsed time.
- Analytical solution preserves the zero-outward repeated-root case and expm1 precision near time zero.
- Three amount nodes show central, peripheral and eliminated percentages, not organ images or patient concentrations.
- Three 0-48 h curves use solid, dashed and dotted styles, separate legends, current-time markers and accessible summary.
- Mode, all four double-compartment inputs and the independent single-compartment inputs survive per-entry navigation/restoration. Missing legacy fields default safely; invalid saved drug arrays are discarded without losing other selection fields.
- Each mode resets only its own inputs. Public Agent preview includes only the selected drug model while in drug research; other topics, Values and whole-body prompts exclude its synthetic state.
- English/Chinese assumptions, equations, ranges and DOI reference mirror Android. No dose, treatment effect or personal organ exposure is calculated.

## Verification

Static project registration, Swift grammar, localized XML parity and Git merge simulations are checked.
XCTest source includes independent Android/SciPy matrix-exponential fixtures, conservation/monotone loss, boundary and repeated-root cases, mode encoding, legacy/invalid restoration and preview isolation.
These are added regression sources, not executed test results. No XCTest, Xcode compilation, native screenshots, IPA or physical-device acceptance is claimed on Windows.
