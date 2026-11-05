# Android health restore conflict review

- Review a verified backup in the native restore flow. Check that a conflicting live record is unselected by default, that choosing its backup version does not write anything, and that a new confirmation is required after returning to the preview.
- Restore one selected conflict and leave another unselected. Verify that the old version remains in local revision history and that the selected backup evidence is attached to the new revision.
- Force a secondary-link write to fail after the selected record is updated. Verify that the update, new revision, original references and receipt all roll back. Retry the same plan after removing the failure.
- Try to replace a deleted record or a record with a new unsaved edit. Verify that both cases reject the requested transaction without removing the edit or importing other records.
- Import the same package again. Verify that neither the replacement revision nor its source link is duplicated without a new conflict and explicit selection.

Validated on Samsung Galaxy Tab Active3 (SM-T575), Android debug 0.1.7.59: 36 focused restore, backup and source-review tests and 87 related table, original-library, migration and export tests passed without skips.
