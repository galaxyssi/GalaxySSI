# Android #4287: complete assessment input provenance

Reference: galaxyssi/GalaxySSI#4287, merge
`ae4a1d48bf8d71e43d2f9e514940d25ead0bc146`.
Prerequisite: iOS #4374 / Android #4286 related-measurement consent.

## Runtime mapping

- `recordLocalCareModelReview` first performs existing live consent, source,
  primary-record and allowed-reference checks. It then requires the current
  record of every available explicitly selected metric. An omitted selected
  input throws `Failure.invalid`, not a revoked-consent error.
- `GalaxySSIHealthCareModelReview.failure` exposes `invalid_health_review`
  with instructions to correct the input within the existing bounded cloud
  continuation. It explains that references are input provenance, not clinical
  relevance, causation or diagnosis. The host never inserts missing references.
- Required references are allocated before optional primary baseline references,
  so the 30-record schema limit cannot discard a selected current input.
  Unavailable selected metrics contribute no invented reference.
- The cloud tool instruction and paired Desktop snapshot response contract both
  require complete selected-input references and explanation of limited relevance
  or missing measurement context. A paired envelope missing them is rejected by
  the same phone-side validator before storage/completion.
- This validates newly recorded assessments only; no migration rewrites previous
  assessments, conversations, plans or clinical data. It does not accept plans,
  set targets or create reminders automatically.

## Verification and parity limits

Added XCTest source cases cover primary-only omission, omission of one selected
input, correction without host insertion, unavailable selected data, reference
budget ordering, and the actual production cloud continuation through error,
corrected recording and successful completion. Existing synthetic fixtures now
produce the complete authorized record set.

The source Android PR also adds an opt-in real WorkManager/paired Codex acceptance
runner. That Android runner is not executable on iOS. No iOS real-provider/process
recovery acceptance run is claimed here. The existing iOS paired Health protocol
still has the read-only snapshot limitations documented for #4374: it does not
expose an on-demand history tool or an interactive remote assessment-tool error
round trip. A rejected final paired envelope is not silently repaired or replayed.
Those paired-protocol parity items remain outstanding.

Windows checks: iOS project structure, changed Swift grammar, localization
placement and whitespace. These do not replace Xcode type-checking, XCTest,
device UI, notification or live provider verification. No IPA was generated.
