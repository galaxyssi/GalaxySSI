# Android report review reminders

The Reminder Center derives its report queue from durable OCR and table import jobs and opens the matching native review screen. It does not copy raw OCR, measurement values, or filenames into the reminder database. The pending, handled, and all views page by the source job time and ID.

- Report review is enabled by default in Reminder Preferences. Turning it off hides the report queue without deleting import jobs or its handling state.
- Marking a reminder handled does not confirm any measurement. OCR jobs stay available until explicitly handled; saving one selected measurement must not imply that all pages were reviewed.
- Completed or undone table batches are handled. A table that is still validating or committing does not present a review action.
- Snooze changes only in-app state for one hour. System delivery for this category is not yet enabled. No report contents are published as system notifications.
- Source state transitions invalidate the queue without reloading it for each file copy or row commit.

`HealthReportReviewDeviceTest` covers a real isolated OCR import, a structured table save and undo, durable reminder actions, keyset pagination, an upgrade from the prior reminder schema, and the native jump to the exact review job. Run the original retention switch regression and the existing reminder and table store tests against the same APK.
