# Android #4337: Complete Microscopic Mechanisms

Source: [Android #4337](https://github.com/galaxyssi/GalaxySSI/pull/4337),
merge `9036622e301ac95b6f8fe4b4364444d532286974`.
Independent formal PR based on main; no Android/Desktop or version changes.

## Integration

The twelve reproductive mechanisms from the now-merged [#4457](https://github.com/galaxyssi/GalaxySSI/pull/4457) are included in the main baseline.
This PR adds only the subsequent 52-mechanism delta. It also scopes the reproductive regression assertion to its own fifteen mechanisms, so a later catalogue expansion does not falsely fail an unrelated fixture.

## Changes

- Adds only the 52 Android delta mechanisms and matching assignments, including the platelet fragment.
- Full composition has 105 cell types and one fragment with exclusive matching mechanism ID/kind, four owned stages and 530 distinct microscopic text keys.
- Rejects orphan/mismatched microscopic owners, macro entries reusing microscopic models and incomplete full catalogues.
- Frozen baseline and staged loader fixtures retain explicitly partial validation; the final installed extended pack requires complete validation.
- Preserves exact Android public content, anatomical chapters and restrictive PubMed references.
- English/Chinese resources add 260 keys each. Existing detail/function/simulation and Agent preview resolve the newly owned model without a duplicate UI path.

Static composition audit compares actual installed iOS resources with Android: 287 entries / 127 mechanisms.
Project/source registration, grammar, localized XML parity and merge simulations are checked.
XCTest regression source covers the stricter ownership invariants. No XCTest, Xcode compilation, IPA, native screenshots or device acceptance is claimed on Windows.
