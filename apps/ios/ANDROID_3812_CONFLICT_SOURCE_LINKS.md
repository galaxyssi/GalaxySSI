# Android #3812: source links for selected replacement revisions

Reference: `f7028ad1a3b07625b3ac3bad02b4959174b5357e`.
The existing iOS selective conflict review already rejects deleted/source-mismatched,
drafted, ambiguous and stale replacements. This follow-up fixes source frames that
were processed before the selected new revisions existed and therefore skipped.

## Change

- After validated replacements are appended in memory, bind only their backup
  source frames through the existing restoreSourceFrames policy, before staging
  originals or committing the archive/receipt. No selection means no extra work.
- Decode the same immutable unlocked input; require exact selected IDs present in
  backup readings and current proposed records. Restrict frames to selected IDs.
- Reuse authenticated existing/staged report mapping and table digest aliases.
  Bind eligible secondary sources to the new selected revision. Unselected
  conflicts do not acquire backup links as a side effect.
- Keep exact source-slot ownership, existing collisions, draft exclusion, ambiguity
  checks and source limits. Do not steal a source reserved by another record or
  bypass skipped-source policy. This is not blanket rebinding of historical links.
- Preserve existing date-only interpretation and Excel date-system fields when
  constructing/remapping table evidence; the older initializer dropped them.
- No schema, encryption, source interpretation, confirmation, permission or
  network/model changes. Preview remains the preselection baseline; this does not
  introduce Android-style detailed per-restore count receipts or claim full parity.

Four XCTest methods live in a new dedicated test file and are registered in the
test target. They cover selected-versus-unselected links and subsequent selection,
new revision identity, report/table aliases, retained date provenance, occupied
slots and stale preview rejection. They are authored only, NOT executed.

## Source Validation

The JS guard checks exact declared hooks and table-field additions, then compares
all other backup code with the immutable baseline. When #4713 is present its exact
finalization normalizer composes separately; no recovery app code is duplicated.
The existing source slot policy remains unchanged. The guard also checks the
dedicated fixture source, four project registration entries and 19 negative source
mutations. These checks do not typecheck Swift or execute restore behavior.

No Xcode/native build, XCTest, real database/file/crash/restart/collision/UI or
performance acceptance, CI inspection, IPA, Android/Desktop edits or auto-merge.
