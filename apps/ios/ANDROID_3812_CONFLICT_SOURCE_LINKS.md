# Android #3812: source links for selected replacement revisions

Reference: `f7028ad1a3b07625b3ac3bad02b4959174b5357e`.
The existing iOS selective conflict review already rejects deleted/source-mismatched,
drafted, ambiguous and stale replacements. This follow-up fixes source frames that
were processed before the selected new revisions existed and therefore skipped.

## Change

- After validated replacements are appended in memory, bind only their backup
  source frames through the existing restoreSourceFrames policy, before staging
  originals or committing the archive/receipt. No selection means no extra work.
- Reuse the immutable payload already decoded by the fresh restore preview work,
  without decoding the whole backup again. Require exact selected IDs present in
  backup readings and current proposed records. Restrict frames to selected IDs.
- Reuse authenticated existing/staged report mapping and table digest aliases.
  Bind eligible secondary sources to the new selected revision. Unselected
  conflicts do not acquire backup links as a side effect.
- Keep exact source-slot ownership, existing collisions, draft exclusion, ambiguity
  checks and source limits. Do not steal a source reserved by another record or
  bypass skipped-source policy. This is not blanket rebinding of historical links.
- Preserve existing date-only interpretation and Excel date-system fields when
  constructing/remapping table evidence; the older initializer dropped them.
- Add optional encrypted restore history, committed in the same archive write as
  the selected revisions and receipt authority. Legacy archives have no fabricated
  history. Generic original staging does not create manual-backup history.
- Count new/duplicate/unreplaced/replaced measurements, added/reused/repaired/
  unavailable originals, new tables, added/reused/skipped source links and missing
  references. Selected sources adjust the baseline counters without double counting
  missing reference keys. Validate bounded nonnegative components before sums.
- Keep the newest 100 detailed receipts without pruning the separate staging
  authority set. The history page initially shows ten and supports older entries,
  current language/date formatting, owner/foreground reload and inactive clearing.
  Counts describe committed outcomes, not current original-file delivery. The
  separate #4713 pending-original recovery remains authoritative for that state.
- Use the unlocked payload SHA256 as an opaque backup fingerprint, not an invented
  Android package ID. No backup format, encryption, source interpretation,
  confirmation, permission, network or model changes; no claim of full parity.

Seven XCTest methods live in a new dedicated test file and are registered in the
test target. They cover selected-versus-unselected links and subsequent selection,
new revision identity, report/table aliases, retained date provenance, occupied
slots, stale preview rejection, receipt counter conservation/bounds, history
trimming, duplicate authority, invalid-detail rejection and generic staging history
preservation. They are authored only, NOT executed.

## Source Validation

The JS guard checks exact declared hooks and table-field additions, then compares
all other backup code with the immutable baseline. When #4713 is present its exact
finalization normalizer composes separately; no recovery app code is duplicated.
The existing source slot policy remains unchanged. The guard also checks the
dedicated fixture source, four project registration entries and 19 negative source
mutations. A separate `check-restore-receipts.cjs` owns the precise receipt hooks,
model/history view, eight app target registrations, 21 localized strings and 16
additional negative source mutations. It composes inverses with the selected
source, finalization and photo-retention checks without copying their app changes.
These checks do not typecheck Swift or execute restore behavior.

No Xcode/native build, XCTest, real database/file/crash/restart/collision/UI or
performance acceptance, CI inspection, IPA, Android/Desktop edits or auto-merge.
