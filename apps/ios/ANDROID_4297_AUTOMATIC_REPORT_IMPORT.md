# Android #4297: automatic report-image import on iOS

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4297
Android merge: `d819bdc362d1b0d86b06bbcb0047d7b3ba5afbf2`.

## Changes

- Replace per-item model-result editors and the supplement dialog in the image-report flow with compression/recognition/save progress and a durable result summary. Local OCR, PDF, table and device capture workflows remain unchanged.
- Keep explicit consent for each single image and the existing paired Desktop private, read-only, no-history, no-tools transport. No offline queue, silent resend or provider fallback is added.
- Reduce the JPEG ceiling to exactly 100,000 bytes at both encoding and transport validation. Try the Android edge/quality sequence with cancellation checks; oversized encoding fails closed.
- Commit the validated model result, measurement revisions, duplicate evidence links and import receipt in one encrypted archive replacement. Revalidate exact job, original/crop, consent, active task and byte bounds before commit.
- Save only valid, dated, unambiguous rows; link duplicates without overwriting user records. Unknown fasting remains unknown. Missing/ambiguous timestamps, invalid units and conflicting same-metric values are skipped rather than opening correction prompts or silently choosing a timestamp.
- Retain skipped/partial originals. Fully imported temporary originals may be released, but explicitly retained originals are preserved. Deletion cleanup cannot treat skipped rows as a successful complete import.
- Persist counts, compressed image bytes and exact record IDs. Reopening a completed receipt does not resend or recreate deleted measurements. Legacy recognized-but-uncommitted reports can finish locally, with no network call or supplement prompt.
- Empty model rows are a valid zero-import result; malformed rows, unknown schema fields and forged units remain rejected. Summary visibility and linked live records refresh on privacy/account/lock/data changes.

## Compatibility

New receipt properties are optional so existing encrypted jobs and outcomes decode unchanged. Existing manual review/draft persistence APIs remain available for older data and other local workflows; their supplement UI is no longer compiled or reachable from report-image import. No Android/Desktop changes, version bump or IPA are included.

## Validation

Added 14 XCTest regression source methods for atomic success/cancellation, receipt replay, missing fasting/date, conflicting/unknown values, revocation, the exact byte limit at commit and transport, duplicates, empty results, original release, legacy local completion (including released images) and receipt decoding. Updated the parser contract test for zero-row outcomes.

Windows validation is limited to project/static checks and Swift grammar parsing. Xcode build, XCTest execution, simulator/device UI, live paired transport and compression quality on real reports have not been verified here.
