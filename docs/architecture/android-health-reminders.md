# Android Health Recording Reminders

Health Center opens a native reminder center with pending, handled, and all
views. Its detail page links to the real manual record editor and supports
completion, a one-hour snooze, and disabling the plan. Reminder preferences
require explicit save. The daily plan and Android notifications are off by
default; the user chooses a local time and a recording category. A 24-hour
pause and configurable quiet hours are independent.

## Persistence And Delivery

- A local calendar date is the identity of a daily occurrence. A SQLite
  transaction creates at most one occurrence per date and preserves its
  scheduled time, zone and selected recording category. Old days are not
  backfilled after a pause or device downtime. Enabling a plan after today's
  schedule does not create a retrospective reminder.
- Encrypted settings and occurrence payloads are bound to their row
  identities. Date, scheduling and state columns are indexes; they are not
  secret. The reminder database contains no measurement values or notes.
  History uses 30-item keyset pages. Stale settings and action revisions are
  rejected, including late UI actions after a snooze or disable.
- One inexact Android alarm wakes reconciliation for the next daily time,
  snooze expiry, or deferred delivery. WorkManager handles the receiver's
  work, and reconciliation also runs after boot, app replacement, clock or
  zone changes, ordinary startup recovery, and opening the reminder center.
  The daily time is interpreted in the device's current zone; DST gaps shift
  forward and overlaps choose the earlier instant. Android can delay the alarm
  and can suspend it during force-stop until the app is launched again.
- In-app presence and user handling are separate from system notification
  posting. A blocked system channel or App setting leaves a usable in-app
  reminder; restoring permission does not replay those suppressed alerts.
  Quiet hours defer eligible notifications without hiding in-app entries.
  Expired occurrences remain in history rather than emitting stale alerts.
  Snoozing explicitly makes a new delivery attempt for the same occurrence.
- System posting uses a stable date-scoped tag and only-alert-once behavior.
  The posting outcome records an Android notification request, not an
  acknowledgment that the user saw it. The default lock-screen public version
  contains no recording category or other health detail.

This increment does not infer any clinical change or continuously monitor
measurements. Versioned data-derived change alerts, report-review reminders,
and real source synchronization failures need separate producers and their
own validation.

## Verification

Version 0.1.7.27 (Android 1440) was built and cover-installed on Galaxy
Tab Active3 (SM-T575). The focused suite passed 272 JVM tests, 236
non-visual device tests, and 35 native UI/lifecycle tests, with no skips.
Reminder center and preferences were inspected on the tablet. Reminder
fixtures used isolated databases and did not change production notification
settings. The physical system-notification, device-reboot, and time-zone
delivery matrix remains open; simulated time and store reopen are not
substitutes for it.
