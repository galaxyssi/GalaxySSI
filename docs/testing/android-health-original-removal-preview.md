# Android health original removal preview

The original detail page shows the selected file name, size, and number
of linked measurements that will remain. It counts active records for the
current profile across all pages, including records linked through secondary
evidence. The preview is computed off the UI thread and dismissed when the
activity leaves the foreground. If the original or the measurement versions
change, the user must review a new preview.

Confirming removes only the selected original file from app storage.
Review-only originals also release their retention marker. Measurement
records, source links, recognition drafts, and original metadata remain.
Copies already backed up or exported are unaffected. This action is not a
secure wipe of the underlying device. The encrypted audit records one
original-file removal without storing the name, digest, or ID.

On Tab Active3 (SM-T575), the Android 0.1.7.78 detail test verified the exact
dialog text, cancellation, removal, and retained measurement and audit
state. The shared-database test verified that a preview with 34 linked
measurements is rejected when a 35th is added, and that removing the
review-only copy keeps the identical archived copy and all 35 measurements.
Both tests used isolated databases and synthetic reports.
