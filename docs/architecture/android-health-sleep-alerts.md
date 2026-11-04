# Android Sleep Change Reminders

Reminder preferences add an opt-in sleep-duration category, a choice of
30/45/60/90 minutes, and same-change merging. A preference is not a clinical
threshold. The default remains off, independent of the daily recording plan.
The reminder center groups health changes separately from recording tasks.

## Evaluation And Evidence

- The current interval is the last seven completed local dates. The baseline
  is the immediately preceding 14 dates. Evaluation reuses the weekly report
  calculation for confirmed self measurements and normalizes hours/minutes
  before computing equally weighted daily means.
- At least five current days and ten baseline days must be usable. An alert
  requires the decrease to reach the selected threshold; missing days,
  insufficient baseline, or an increase do not create an alert.
- A changed sleep metric revision, date, zone, rule/configuration, or
  privacy-policy revision triggers a new indexed calculation. The input
  fingerprint is committed with the alert transition, so unchanged input
  does not repeatedly decrypt the same records or append duplicate audits.
- The encrypted occurrence retains its first trigger and latest qualifying
  snapshot, including daily values with gaps, means, coverage, zone, data
  revision, rule version, threshold, and calculation time. Notes, profile
  context, and original attachments are excluded. Links use the evidence
  date range and metric revision; a newer revision is not shown as the
  source of an older conclusion.
- Computation requires local confirmed-metric authorization and records
  its scope in encrypted access history. Revocation closes the current
  episode and hides saved evidence until authorization is restored.

## Episodes And Delivery

The durable ledger has at most one current sleep episode. With merging
enabled, a continuously qualifying change updates that episode without
resetting delivery or completion. A resolved or insufficient window closes
the episode. Without merging, a new qualifying date may create a new episode
only after a seven-day cooldown; the same date cannot reopen a current
episode. Completed or snoozed states and explicit category disable survive
reopen, with stale actions rejected by revision. The SQLite migration adds
trend tables without replacing existing recording plans or occurrences.

Record commits enqueue coalesced work for the enabled category. The existing
reminder worker and inexact alarm also reconcile at the next local date,
snooze expiry, app startup, boot, and clock/zone changes. The notification
uses a stable episode identity and follows the shared system-permission,
quiet-hours, and lock-screen settings. It never includes measurement
values; with lock-screen redaction enabled its public version is generic.
In-app handling is separate from notification posting. This is not
continuous monitoring, and Android may delay background work.

Report review and device synchronization remain distinct future producers;
neither is represented with fake health reminders.

## Verification

Version 0.1.7.29 (Android 1442) was built and cover-installed on Galaxy
Tab Active3 (SM-T575). The focused suites passed 286 JVM tests, 248
non-visual device tests, and 42 native UI/lifecycle tests, with no skips.
The device preference screen was inspected without enabling the real rule.
Isolated tests exercised confirmed record calculation, deduplication,
version-one database migration, evidence changes, snooze, completion, and
visible permission revocation. Real lock-screen notification delivery,
physical reboot, and time-zone changes remain separate acceptance items.
