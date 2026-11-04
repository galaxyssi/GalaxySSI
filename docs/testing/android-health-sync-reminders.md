# Android health sync reminders

The Data Connections section in the Reminder Center reflects recorded foreground Health Connect outcomes for selected data types. It does not infer a failure from old measurements, a disconnected Bluetooth screen, a paused attempt, or a successful sync with no new data.

- Each data type keeps its latest encrypted connection incident. Repeated failures update the same incident, including the latest reason and attempt time. A new failure after successful recovery receives a different ID.
- The incident and terminal checkpoint commit in one transaction. A retry preserves any outstanding incident and does not lose its acknowledgement. Existing failed checkpoints are readable after upgrade.
- A successful sync, including one without new measurements, resolves the incident. Acknowledging a reminder changes only its handling state, not the source checkpoint or saved measurements.
- The reminder opens the matching coverage card. Retry and permission actions remain in the source screen and require the normal user interaction.
- A new incident can also enter system delivery if the user enabled system reminders and Android permission allows it. The encrypted delivery receipt is independent of handling, and repeated failures cannot reset it. Existing incidents without a receipt remain in app.
- Quiet time and pause defer pending delivery. Handling, recovery, deselection, or disabled notifications remove obsolete system notices. The lock-screen version is redacted, and the normal notification contains no metric or health values.
- Tapping a notification opens the matching coverage card. No notice triggers a retry, health monitoring, or background sync.

`HealthSyncDeviceTest` uses a controlled provider and isolated databases to exercise repeated transport and permission failures, continuation, stale acknowledgement rejection, no-new recovery, and native Reminder Center navigation. This does not substitute for tests with a real authorized Health Connect source.

`HealthSyncNotificationDeviceTest` verifies persisted delivery, quiet and pause, stale and cancelled notifications, recovery of an already visible notification, and native Android posting and cancellation on an isolated silent channel.
