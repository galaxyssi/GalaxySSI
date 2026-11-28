# Android #3797: retained ZIP resave and token receipts

Reference: `eba1a449e`. Existing merged iOS #3826 supplies encrypted original ZIP
history and destination byte/SHA verification; #3830 supplies sharing and #3929
linked record bundles. This follow-up fills the missing historical ZIP save action
and repeated save receipts. It does not duplicate the existing bundle/sharing code.

## Change

- Add optional latest-save receipt and last-verified timestamp to existing export
  entries. Legacy entries remain readable without invented tokens or timestamps.
  Keep the same encrypted, atomic, owner-bound history file and existing 50 cap.
- Both initial original ZIP export and history resave authenticate the retained
  artifact before beginning a save. Require the exact export ID, timestamp,
  originals manifest, bytes and hash. Persist a new pending token before presenting
  the document picker. Share-only preparation is not mislabeled as a save.
- Complete only that owner's/dataset's exact pending token and immutable export
  snapshot. Late/repeated callbacks cannot finish newer saves. The legacy completion
  API cannot bypass a token-aware pending save. Existing coordinated bounded
  destination byte/hash verification is unchanged and performed off the main actor.
- Verification updates the last verified time. A later failure or interruption
  does not erase earlier verified success; latest status remains separate.
- Process-local weak request tracking prevents another visible history reload
  from interrupting a live picker/verification. Lost requests become interrupted on
  recovery. Exact-scope completion and recovery are serialized on MainActor; this
  is NOT a cross-process lease or a measured crash/durability guarantee.
- History observes owner-filtered updates, reloads the selected snapshot, warns
  that the ZIP is unencrypted and offers another Files save. Preserve callback
  state while the system picker is active; hide sensitive content while inactive.
  Status/verified time remain visible even when a retained artifact was pruned.
  Single-original saves, external share delivery status and original bytes remain
  unchanged. Verified bytes do not prove provider durability or recipient delivery.

## Verification

Six dedicated XCTest cases authored, NOT executed: legacy decoding; repeated-save
failure retaining prior verified time and old-callback rejection; live/lost request
recovery; owner/dataset isolation; changed manifest and legacy bypass refusal;
exact destination hash/length verification. No existing large test file changes.

The source guard checks exact new hooks, 12 Xcode entries, six localization keys
and 20 negative source mutations, then compares all unrelated storage, verification,
sharing and UI code with main after separately owned companion inverses. Source
checks do not typecheck Swift or execute these scenarios.

No native Swift/Xcode build, XCTest execution, storage faults, document-provider,
file-picker/callback/lifecycle/UI, real restart/concurrency, performance or delivery
acceptance, CI inspection, IPA, Android/Desktop edits or automatic approval/merge.
