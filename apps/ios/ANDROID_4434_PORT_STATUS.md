# Android #4434 iOS Port

Pinned source: `3327febe8406fb5ee5cf30dc0734ef6c4e2cbdcc`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4434

## Review Scope

Base is main. Inherits OPEN formal #4510 and its documented predecessors;
none is assumed merged. Full main diff includes inherited work, not only this
feature. Incremental review base: `1a56bcb91185a597389bb20cc49f22bd395aff0b`
(#4510 head). Only iOS files change; no Android/Desktop changes or IPA.

All eleven original files have pinned hashes/dispositions: five production
files, two resource XMLs, one unit-test and one device-test reference, Android
version and architecture documentation. See ANDROID_4434_SOURCE_INVENTORY.json
and ANDROID_4434_PORT_COVERAGE.json. No external medical claims are added.

## Implementation

- Add Compare models beside the preserved single- and two-compartment explorers
  in Drug Pathways. Three stable, wrapping tabs retain visible labels and their
  selected state; mode changes do not replace the surrounding ADME navigation.
- Reuse the unchanged native two-compartment kernel. Start at 100 central units
  and elimination 0.10/hour for all scenarios. Preserve the authored exchange
  pairs (0, 0), (0.30, 0.15), (1.00, 0.40), without recombination. Comparison is
  normalized central amount, not concentration, dose, response or risk.
- Compare the selected two-compartment amount with 100*exp(-k10*t), retain the
  signed difference (two minus one), and compute the shared central-amount
  minimum/maximum over all three scenarios. Validate finite time in 0-48 hours;
  selected time is 0-192 quarter-hour steps, default four hours/exchange scenario.
- Render 193-sample immutable profiles, a 42/255-alpha scenario envelope, 0/50/100%
  and 0/24/48 axes, solid orange two-compartment/dashed green one-compartment
  curves, selected-time guide and two point markers. Preserve original day/night
  palette roles and values; chart height follows the original 144+3*caption-font
  rule. Exact accessible values and legend are adjacent to the decorative plot.
- Add reset, rates/time/amount/gap/range, visible synthetic/evidence limits and
  equation/independent-validation links. The scenario envelope is explicitly not
  a confidence interval; numerical checking does not establish experimental or
  clinical validity. No observations, model service or patient prediction.
- Encode seven bounded integers. Accept the original five-item state only for
  single/two modes and migrate to default comparison settings. Restore scenario
  and elapsed time independently of distribution and elimination settings.
  Invalid lengths/modes/scenarios/times/rates are rejected, not clamped.
- Update both Agent context branches to include only the selected comparison,
  distribution or elimination context. Retain existing confirmation/handoff;
  comparison values do not appear on other research/public/personal surfaces.
- Extract/register all eleven exact English/Chinese pairs and three Swift files
  including focused XCTest source. Add source fixtures for the pinned independent
  four-hour result, all scenario/time profiles, no-exchange reduction, mass and
  envelope accounting, legacy/new state, reset/restoration and bilingual context.

## Source Verification And Limits

Passed source checks cover all eleven original hashes/dispositions, exact resources,
frozen rates and formula wiring, unchanged numerical kernel, bounded state
codec, chart layout, research/context/confirmation wiring and predecessor source
contracts. Eight changed/added Swift files passed grammar-only parsing after
conditional directives were removed; project structure and whitespace checks
passed separately.

No Android tests, XCTest execution, Swift type checking/Xcode build, native
numerical/UI/render/gesture/recreation/VoiceOver acceptance, simulator/device
launch or IPA. Android's matrix fixtures are references, not proof of Swift
execution. No experimental or clinical validity is claimed. Source wiring does
not establish screen parity; inherited runtime/vector acceptance gaps remain.
