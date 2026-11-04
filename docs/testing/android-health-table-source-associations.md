# Android health table source associations

Table mapping (h10) skips duplicate measurements by default. Before saving, the user can choose to link exact duplicates to the uploaded original. The import rechecks the existing observation before linking. A link records the confirmed table evidence for that observation revision; it does not modify the measurement, its notes, or its primary source. Undo removes links added by that import without deleting the reused measurements.

Original detail (h28) pages through primary and linked measurements in time order. Both sources use indexed cursors; each supplies at most 31 candidate keys before the results are merged and deduplicated. Original-scoped record exports use the selected evidence and can include the exact bytes of that original. General record exports continue using the primary source.

Regression coverage:

- Import two distinct CSV originals with the same measurement. Verify that only one measurement exists and that the second original shows the measurement and linked export action.
- Export the second original with records. Verify the original file bytes and the evidence ID and hash; confirm that the primary source in storage did not change.
- Verify the default skip behavior, source encryption, the revision check, independent batch undo, and ordered paging across 63 measurements.

Validated on Samsung Galaxy Tab Active3 (SM-T575), Android debug 0.1.7.56: 7 source-detail and structured-preview tests plus 125 storage, import, export, and migration tests passed without skips.

This change does not link OCR duplicates or include secondary associations in full backup and restore.
