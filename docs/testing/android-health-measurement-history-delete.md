# Android scoped local measurement deletion

Privacy & Data opens a local deletion screen for a single measurement
type. The preview shows the stored date range and counts by source,
including records that were previously soft-deleted but still retain
revisions. Nothing is removed until the user confirms.

The store authenticates the records as it scans bounded keyset pages.
The transaction rechecks the metric revision and reconciles the date
range and source counts against the preview. It removes local records,
revisions, edit drafts, and measurement links for the selected metric,
and invalidates derived views. Other metrics, profile entries, and
report original bytes are not removed. The source-specific Health
Connect path shares the same transaction and retains its source filter.

Pairing, permissions, provider data, sync settings and checkpoints,
existing exports, and backups are unaffected. Records can be imported
again. The encrypted privacy log records the scope and outcome, not
measurement values. This is logical removal, not a forensic storage wipe.

Android 0.1.7.77 passed 54 focused instrumentation tests on Tab Active3
(SM-T575), with no failures or skips. The native privacy flow verified
manual, OCR, and Health Connect counts, deletion of only the selected
metric, retention of the report original, and the scoped privacy event.
The suite also covered the previous source-specific deletion workflows.
All deletion fixtures used isolated synthetic records.
