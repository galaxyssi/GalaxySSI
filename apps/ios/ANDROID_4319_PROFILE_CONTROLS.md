# Android #4319: simplified profile controls and distinct Health icons

Source: https://github.com/galaxyssi/GalaxySSI/pull/4319

Android merge inspected: `9d6757100f17c36abcce543faba1e3c780f93a5d`.
Follow-up to iOS #4424 / Android #4318; no preceding theme/navigation changes
belong in this PR's main-based diff.

## Mapping

- The profile row and selection sheet are titled Sex. Only Male and Female
  appear, in that order, with the current selection checked and accessible as
  selected. Tapping a choice changes the current draft; the existing Save
  Profile action persists it. Cancel/dismiss never chooses a default value.
- Legacy unspecified/other values display Not specified, with neither option
  checked. They remain decodable and are not overwritten by opening/cancelling
  the sheet or by unrelated profile edits. The model's legacy cases remain.
- Remove physiological-context input from the profile form. Existing context,
  analysis versions, consent scopes and other profile data remain unchanged;
  no schema migration or deletion. Explicit Clear Profile keeps its existing
  separately confirmed destructive behavior.
- Care uses the native heartbeat symbol; Profile and its header use the existing
  profile-record symbol; Body retains the already distinct human-body symbol.
  These are native SF Symbols available on iOS 15, not new raster logos or
  copied Android vector paths. Feature order, tint and navigation are unchanged.
- Backgrounding dismisses the new selector and clears the draft as before.

## Verification

Focused XCTest source covers the two-choice policy, nil/cancel handling, legacy
decode round trips, encrypted save/reload of both choices without losing hidden
context, unrelated name edits, distinct symbols and native symbol availability.
No tests executed, per request.

Static project registration, Swift grammar and whitespace checks only. These
are not Xcode compilation or native UI validation. No simulator/device runs,
screenshots or IPA on Windows. Native symbol rendering, selected/cancel gestures
and sheet behavior still require native review. iOS only; no version bump.
