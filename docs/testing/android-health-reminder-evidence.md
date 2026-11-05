# Android sleep reminder evidence

Merged sleep reminders retain both the first trigger and the latest
assessment. The detail screen can switch between the saved dates, coverage,
chart, comparison and rule metadata, without changing the reminder state.
Only the selection is saved across activity recreation, not the displayed
measurements. If the user revokes access to confirmed metrics, the detail
no longer shows the chart or its evidence links.

Recent and baseline record links carry the selected snapshot's exact
window and metric revision. A revision mismatch does not open substitute
records. The weekly report handoff carries only the sleep scope and its
version stamp. It requires explicit refresh if the linked records have
changed, preserving the dates; raw records are not selected for export.

Android 0.1.7.71 passed 54 focused instrumentation tests on Tab Active3
(SM-T575), including evidence switching and recreation, stale cohort and
report behavior, current baseline and weekly navigation, privacy revocation,
and existing reminder/weekly report regressions. Tests used isolated
synthetic records. This is not physical notification delivery or external
health provider acceptance.
