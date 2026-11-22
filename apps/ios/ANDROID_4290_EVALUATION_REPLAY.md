# Android #4290: duplicate evaluation consistency

Reference: galaxyssi/GalaxySSI#4290, merge
`aba16a74bc1c28991502d27cc1ec8a988edf61fb`.

## Platform comparison

Android evaluates outside its store transaction, then submits an input token,
evaluator version, expected settings and expected concern revision. Its fix checks
for a committed input replay before rejecting an obsolete expected revision, while
retaining current-consent and evaluator-version checks.

iOS does not expose that stale-evaluation submission API. The production
`reconcileLocalCare` method is synchronous and MainActor-isolated. It reloads the
encrypted archive, validates current consent, computes using current source and
confirmed context, and publishes only changed assessment/maintenance/warning or
comparison state. Later user pauses are preserved. Deletion stores an input digest
and does not recreate the concern for unchanged source data. Optimistic user-edit
checks remain separate and still reject obsolete concern snapshots.

No runtime token cache or parallel commit API is introduced merely to resemble
Android's storage implementation. This PR adds focused iOS source regressions for
the corresponding existing contracts.

## Source coverage

Eight isolated XCTest cases cover:

- Initial replay through an independent store instance: same concern/history and
  byte-identical encrypted archive, with no rewrite.
- Updated-input replay: same committed revision and comparison, no extra history.
- Replay after user pause: preserve the exact paused concern and archive.
- Replay after deletion: preserve the deletion marker and original measurements.
- Genuinely new source data after deletion: a new concern is permitted.
- Confirmed context: evaluate current saved context; stale user edits still fail.
- Current privacy opt-out and renewed permission epoch, without stale cached consent.
- Two task callers using independent store objects: one initial concern, serialized
  by the production MainActor boundary.

The Android research-consent fixture correction excludes the primary metric from
the additional choices. iOS already filters it in `relatedLocalCareOptions`, with
existing coverage in `GalaxySSIHealthCareRelatedContextTests`; no duplicate UI edit
is needed here.

## Verification limits

These are XCTest sources, not executed results. Windows supports project structure,
Swift grammar, localization-placement and diff/merge checks only. No Xcode
type-check, device/UI, live provider, or IPA acceptance is claimed.

The task test is not simultaneous SQLite writers or independent OS processes.
The archive's atomic file replacement is not claimed to provide cross-process
transaction isolation. A future second-process writer would need its own
coordination design; this change concerns the current single-process iOS API.
