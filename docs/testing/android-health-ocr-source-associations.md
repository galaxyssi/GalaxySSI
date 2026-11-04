# Android health OCR source associations

In recognition review (h07), confirm each draft against the visible original. When a verified draft exactly matches an existing OCR measurement, the row offers to view that record or select the original for linking. Selecting a link does not select a new measurement. A separate confirmation shows the new and linked counts and is reset when selections change or the screen is recreated.

The batch is atomic. It checks the draft version, source job and original ID, and the expected target revision before writing. A stale or newly conflicting item rolls back the entire batch. A link keeps the encrypted page, region, raw evidence, and hash for the reviewed original without changing the stored measurement. Reopening review recognizes the linked candidate. Original detail (h28) and original-scoped export use the selected original's evidence.

The database upgrade preserves the authenticated payload of table links from version 10. Table undo only removes the links for its own table batch.

Validated on Samsung Galaxy Tab Active3 (SM-T575), Android debug 0.1.7.57: 23 review, source preview, and PDF tests plus 87 table, migration, original-library, and export tests passed without skips. The native test used two synthetic report originals and verified selection across recreation, fresh consent, exact evidence, and one stored measurement.

The duplicate policy still distinguishes OCR, table, and manual sources. Full backup and restore of secondary associations are not included in this change.
