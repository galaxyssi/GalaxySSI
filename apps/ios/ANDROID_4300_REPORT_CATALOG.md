# Android #4300: expanded report catalog and recognition feedback

Reference: galaxyssi/GalaxySSI#4300, merge
`f5a00cfd6cc4668f97c1b8b0cd36ac6d5baf26dd`.

## iOS mapping

- Extend the shared metric catalog from 27 to 47 metrics: blood cell indices,
  differential counts/percentages, albumin, total protein, total/direct
  bilirubin, ALP, GGT, urea and blood urea nitrogen. The existing recording,
  search, table mapping, review, trend and export views use this catalog.
  Keep existing persisted metric IDs unchanged; add localized Chinese titles
  and aliases and English fallback titles.
- Extend local OCR unit patterns and exclude specimen-ambiguous bare labels
  such as RBC, ALB, TP and their corresponding Chinese short names. Explicit
  blood-test labels remain accepted; no assumption that a urine result is a
  blood test.
- Report instructions include all metric titles and aliases and explicitly
  distinguish measurements, specimens and samples. Optional omission metadata
  uses only bounded integer counts, never names or private omitted row data.
  Ambiguous multi-person/sample results fail closed. Existing replies without
  these optional keys remain supported.
- Separate unreadable-image, out-of-catalog-only and ambiguous-sample failures
  from malformed or invalid-row replies. Preserve supported results and show
  omission categories via the existing localized result summary. Stored local
  counters allow at most 160 returned-plus-omitted rows; accepted rows remain
  capped at 80. Model-supplied local rejection counters remain prohibited.
- Normalize equivalent unit spellings only (superscript exponents, micro sign,
  multiplication prefix and lowercase liter suffix). Never convert values or
  substitute counts for percentages or one analyte for another.
- At the response deadline, requery the exact same request. Authenticated active
  work gets at most 90 seconds and completed work at most 30 seconds of grace,
  once only. Missing/unknown gets no grace; terminal failure is not presented
  as a phone timeout. A late reply wins and images are never resent for grace.

## Boundaries

Android version numbers are not copied into iOS. This is iOS-only and builds
on the separate #4299 port. No new HealthKit scopes, durable private outbox,
provider fallback, CI change or IPA build is included.

Added XCTest source covers catalog/prompt bounds, local OCR ambiguity, unit
spelling, omission schemas, stored counters, deadline probes, bounded grace
and terminal reply races. Windows static structure/grammar checks are not an
Xcode compile or XCTest/device/live paired-transport execution.
