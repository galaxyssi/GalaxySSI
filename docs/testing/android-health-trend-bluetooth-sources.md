# Android health trend Bluetooth sources

Confirmed Bluetooth readings retain a keyed, opaque device group in their
encrypted observation, alongside the captured device label. The database
indexes the opaque value for bounded trend pages and device discovery.
Neither the Bluetooth address nor the device group is included in ordinary
record JSON exports. Password-protected health backups retain the group so
restored readings from distinct devices can still be separated.

The trend device picker distinguishes duplicate names with a short opaque
suffix. The selected group is applied to the chart, its calculation audit,
and contributor pages. The record revision shows its own captured device.
Renaming a device does not create a new group. Legacy readings lacking an
identity are still visible under all sources, and are not inferred from a
device name. After a backup is moved to a different installation, its
existing groups remain distinct, but new pairings on that installation are
not automatically linked to the restored identifiers.

The tests use synthetic Bluetooth receipts and isolated databases. They
cover identical readings from same-name devices, rename, edit, legacy data,
the encrypted backup round trip, and native trend-to-contributor navigation.
Commercial monitor pairing and address rotation are not exercised.

All 127 tests passed without skips on a physical Tab Active3 (SM-T575)
with 0.1.7.68: 28 targeted tests and 99 chart, sync, migration, import,
privacy, and export regressions.
