# Android #3867: photo collection retention follow-up

Reference merge: `3cadd4491e428bd174a5e496172d4463d2510701`.
The earlier iOS port #3912 already handles ordinary import defaults. Photo
collections still always kept originals and could promote temporary shared files.
Current Android passes the resolved retention choice into a persisted photo batch.

## Integration

- Reuse the existing encrypted retention setting and one-import picker. Capture
  the choice before camera/album entry; refresh the archive and reject a stale
  draft version or unreadable setting. Carry the exact choice through inspection.
- Freeze the choice in an optional photo-batch field. Missing legacy values mean
  keep, as on Android. New programmatic captures resolve the saved default too;
  continuing/retaking an existing batch cannot silently change its choice.
- Reuse the existing review-only original marker. A new review-only capture does
  not demote a previously saved deduplicated original. An explicit keep can promote
  a temporary source without recreating its existing recognition task.
- Add an optional encrypted photo cleanup inventory containing exact original
  metadata. It identifies photo-owned temporary sources after replacement/discard
  or reopening; it is not a second settings store. Keep all existing bytes/index
  writes inside the restore lease and archive commit path.
- Retry cleanup after photo edits/capture and when the photo view opens/returns
  active. Revalidate current inventory, temporary marker, draft/review/job usage,
  exact original metadata and the existing source-in-use guard under the lease.
  Reject mismatched inventory keys and non-image entries without deleting files.
  Commit the existing removal ledger/audit before byte cleanup. Pending deletion
  or faults retain retry state. A later permanent promotion only drops inventory,
  never deletes the promoted file. Notify index/review consumers after the lease.
- Harden the existing quick-report release gate: no active photo draft, pending
  review or other unfinished/partial/unconfirmed/skipped job may share the source.
  One cancelled job cannot release another consumer's original. Existing model
  release qualifications remain; local OCR without completion evidence remains
  available for review rather than being erased as an assumed success.
- Update camera/album wording and Chinese resources so taking a photo no longer
  falsely promises permanent retention regardless of the selected policy.

## Boundaries

No retroactive cleanup of legacy kept photos. Review-only bytes remain encrypted
while still needed for review/recovery; this is not immediate deletion, background
execution, a disk-space guarantee or secure physical erasure. A failed cleanup
does not become a successful deletion notice. Existing saved originals, readings,
job results, permissions, model/network execution and portable backup format are
not replaced. The archive fields are additive and optional.

Seven Swift fixtures are authored for frozen choice/retake/stale choice, kept-source
deduplication, orphan cleanup after reopening, shared consumer exclusion, legacy
decoding, malformed cleanup inventory and explicit keep promotion without job replay. They are NOT executed.

`node apps/ios/tools/check-photo-original-retention.cjs` checks approved source,
five resource entries, retained baseline fixture source, Android reference and
29 negative source mutations. These checks do not run Swift or prove native
correctness. No Xcode build, XCTest, camera/picker/device/fault/lifecycle/cleanup
acceptance, CI inspection or IPA is performed. Full parity remains unverified.
