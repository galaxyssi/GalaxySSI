# Android Bluetooth device history deletion

The Devices & Data Sources inventory opens the selected device's history.
Deletion is separate from collection and pairing. The confirmation shows
the device, the number of stored measurements (including previously
removed records that retain revisions), and the earliest and latest
measurement dates. The count and blood-pressure revision token must
still match inside the deletion transaction. Cancellation and stale
previews do not change measurements.

The transaction validates the authenticated device group before removing
each selected row, its revisions, edit draft, and measurement-to-source
links. It walks bounded batches and commits them together. The metric
version changes once to invalidate dependent results. Stale editors
cannot recreate a draft for a deleted measurement.

This is logical removal from the active app database, not a forensic
storage wipe. Other devices and manual measurements, Bluetooth settings
and receipt checkpoints, source files, previously created backups and
exports are unchanged. A device can still send more measurements.
The encrypted access log records the purpose, dates, and count without
recording the device name or ID.

Android 0.1.7.74 passed 58 focused instrumentation tests on Tab Active3
(SM-T575), with no failures or skips. New coverage includes cancellation
in the native dialog, a stale preview after a new reading, rollback after
the first batch of a 34-record deletion, preservation of same-name devices
and manual rows, and removal of revisions and stale edit drafts. The
tests used isolated synthetic measurements, not actual device history.
