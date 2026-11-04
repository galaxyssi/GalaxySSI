# Android Health Sync and Recovery

The native Sync and Data Coverage screen is reachable from Devices and Data
Sources. Opening it only checks availability, authorization and saved
metadata. The user explicitly confirms a foreground sync for the types
selected in Health Connect authorization. There is no periodic worker,
background read permission, or live monitoring claim.

- Raw measurement types use independent Health Connect change tokens.
  The token is obtained before the first bounded snapshot, so changes
  during the snapshot are still available. A first run checks the preceding
  24 hours; saved snapshot cursors are resumed after interruption.
- The source cursor advances only after the entire page is handled.
  Batches of up to 120 observations commit with their counts and coverage
  in the same database transaction. A replay uses the same keyed source ID
  as manual import and cannot duplicate or restore a removed observation.
  Tokens and checkpoints are individually authenticated and encrypted.
- Expired cursors rebuild from the last successful sync with an overlap,
  bounded to the latest 29 days without extra history permission. An
  unverifiable older gap stays visible. A rejected snapshot pagination
  cursor can restart the same bounded range without repeating writes.
- Steps use the platform aggregate for completed calendar days, a stable
  zone selected at the first sync, and a bounded catch-up with a two-day
  overlap. No raw step segments are summed by GalaxySSI.
- Sync distinguishes unavailable, unauthorized, network failure, local
  provider transport failure, timeout, interrupted, and successful with
  no new measurements. Last success and latest observed source time are
  different values. A failed page keeps the last committed checkpoint.
- Imported observations are local copies, not a mirror. Provider deletions
  are reported without erasing local history. Replayed or changed source IDs
  do not overwrite existing copies or user edits. Existing Bluetooth
  reception remains an explicitly connected foreground workflow; the
  sync page reports the latest saved receipt but does not query the device.

References: [Health Connect sync guidance](https://developer.android.com/health-and-fitness/health-connect/sync-data)
and [changes-token API](https://developer.android.com/reference/kotlin/androidx/health/connect/client/HealthConnectClient).

## Verification

Galaxy Tab Active3 was cover-installed with 0.1.7.34 (1447). The native
missing-provider and disconnected Bluetooth states were inspected; the
existing observation database opened at schema 6. All 121 focused device
regressions passed without skips. The isolated gateway tests covered
snapshot and change-page resume, expiry, pause, overlap, permission loss,
timeouts, atomic rollback, and duplicate/deleted-source behavior.
This tablet did not have Health Connect installed, so those fixtures do
not establish real provider sync or permission acceptance.
