# Android #3781: backup generation/save ownership

Reference: `d1f717577`. Merged iOS #3851 already has encrypted history, private copies,
recovery, repeat saving and coordinated destination verification. The Android
repository excludes active backup operations from interrupted-state reconciliation.
The missing iOS ownership and picker callback binding are corrected here.

## Implementation

- Add optional generation/save UUIDs to history entries. Legacy decoding does not
  invent tokens or verified timestamps. Keep existing history encryption/context,
  package format, 100-entry history and two-copy retention, bounded byte/hash
  verification and generation publish sequence outside exact producer checks.
- New generation/save requests bind owner/history-directory scope, operation kind,
  immutable entry snapshot and token. Weak process-local request tracking prevents
  recover() from interrupting another visible operation's live producer or picker.
  Lost/released requests recover as interrupted; generation still recovers a valid
  already-published private package through the existing hash check.
- Authenticate current private copy and immutable metadata before persisting a new
  save token. Finish only the exact owned pending token. Legacy ID-only APIs remain
  compatible with old entries/tests, but cannot bypass token-aware operations.
  Later failed/interrupted saves retain earlier lastVerifiedAt.
- The Files presenter carries an immutable request and is keyed by its token. Its
  callback passes that request explicitly instead of reading whichever request is
  now in parent state. Both pre-verification and post-await UI identity guards
  reject old callbacks. Verification targets a captured history owner, never a new
  profile's computed store. Owner changes/runtime clearing release current authority
  and clear presentation state; late results cannot repopulate cleared UI.
- Observe owner-filtered history changes and recover on foreground entry, show
  pending save status, and disable duplicate live saves. Release generation ownership
  on failure/reset before recovery; generation/verification reject duplicate starts.
  A current background result is reset rather than leaving a finished worker
  holding live generation authority. Older tokens still cannot clear newer work.

## Limits And Validation

This is MainActor serialization plus process-local weak ownership, not an OS
cross-process lease, fsync guarantee or native crash/provider-delivery acceptance.
Destination bytes matching do not prove that the provider will retain them. No
changes to restore records/files, model/network, permissions, Android/Desktop,
version, CI policy or IPA. No full Android asynchronous-backup parity claim.

Seven dedicated Swift cases authored, NOT executed: legacy decoding; live generation
and legacy-bypass refusal; old save callbacks and retained verified time; live/lost
save recovery; foreign/forged request isolation; unavailable-key receipt failure;
changed metadata/corrupt private copy refusal. Fixtures use synthetic package bytes,
not complete portable archive integration. Existing large fixture file unchanged.

Source guard checks exact new hooks, eight Xcode entries, one localization key and
23 negative mutations. Existing crypto/copy/verifier/prune tail and generation
write sequence are compared directly to main. Independent restore view inverses
compose separately; no restore application code is duplicated.

No Swift/Xcode build, XCTest execution, picker/callback/lifecycle/concurrency,
storage-fault/restart/performance/provider acceptance, CI inspection, IPA or
automatic approval/merge. Source checks do not establish native correctness.
