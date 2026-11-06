# Android Health reminder delivery

## Delivery and handling

- Daily recording, sleep change, report review, and connection alerts share the same pause and quiet-hours rule. An eligible waiting notification remains waiting until both windows have ended. Pausing withdraws affected visible system notifications without marking their in-app reminders as handled.
- Delivery and handling are separate. Resuming does not replay an already posted notification. A due notification blocked by the app notification setting or system permission remains available in the reminder center, without replay when permission returns.
- After a wall-clock rollback, a daily occurrence or sleep alert is not eligible before its persisted due or snooze time. Future eligible deliveries are scheduled again; stale occurrences still follow the existing freshness cutoff.

## Verification

- The routine delivery tests use an isolated encrypted store, an injected clock, and an isolated silent Android notification channel. They cover a real notification post and withdrawal, persistence across store reopen, overlapping pause and quiet hours, rollback after snooze, permission denial, and cancellation if handling races with posting.
- The settings test verifies that edits require Save, the pause boundary is visible, Resume clears it only after Save, and the Save action stays visible while scrolling.
- The tests do not change the device clock, system notification permission, or lock-screen settings. Physical permission revocation, reboot, and time-zone changes are separate acceptance cases.
