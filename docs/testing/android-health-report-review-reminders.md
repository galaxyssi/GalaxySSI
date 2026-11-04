# Android report review reminders

The Reminder Center derives its report queue from durable OCR and table import jobs and opens the matching native review screen. It does not copy raw OCR, measurement values, or filenames into the reminder database. The pending, handled, and all views page by the source job time and ID.

- Report review is enabled by default in Reminder Preferences. Turning it off hides the report queue without deleting import jobs or its handling state.
- Marking a reminder handled does not confirm any measurement. OCR jobs stay available until explicitly handled; saving one selected measurement must not imply that all pages were reviewed.
- Completed or undone table batches are handled. A table that is still validating or committing does not present a review action.
- Snooze changes the in-app state for one hour. If system reminders are enabled and permitted, an unhandled report can be posted again after that hour and quiet time.
- Newly ready reports and explicit snoozes use a durable delivery queue separate from handling. Disabling the category or system reminders leaves the report in app and does not replay the old notification backlog after re-enabling.
- Notification text is generic, with a redacted public lock-screen version. The tap target opens the exact review job; the notification contains no file names, values, or raw recognition.
- Source state transitions invalidate the queue without reloading it for each file copy or row commit.

`HealthReportReviewDeviceTest` covers a real isolated OCR import, a structured table save and undo, durable reminder actions, keyset pagination, an upgrade from the prior reminder schema, and the native jump to the exact review job. Run the original retention switch regression and the existing reminder and table store tests against the same APK.

`HealthReportNotificationDeviceTest` checks dispatch across quiet time and pause, durable deduplication, snooze and permission handling, stale source reconciliation, and the native notification builder. With existing notification permission, it also posts and cancels on an isolated silent channel without changing the app's configured channel or permission.
