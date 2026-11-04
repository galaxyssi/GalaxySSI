# Android Health Devices and Sources

The health overview and function page open a native sources screen. The
screen distinguishes platform availability, device capability, and stored
local measurements. No connector or sync is inferred from any of these.

- Health Connect availability uses the [official AndroidX SDK probe](https://developer.android.com/reference/androidx/health/connect/client/HealthConnectClient). Available
  devices can open system settings; install/update cases can open the official
  Play listing. No health permissions are declared or requested by this screen.
  The legacy exported callback service is excluded until an integration needs it.
- Bluetooth LE hardware support comes from Android's package manager. No scan,
  pairing, vendor login, or background collection is started.
- Reports and Tables displays separate counts of local original entries and
  confirmed observations with an original link. A pending report is not a
  measurement. Manual Entry shows the latest non-future, non-deleted self
  measurement from the manual source, not its insertion date.
- Source metadata loads off the UI thread. On pause, the content is removed,
  in-flight results are invalidated, and the screen reloads on return.

This increment does not implement Health Connect read consent, Bluetooth
collection, or synchronization. Connection-specific metric scopes, revocation,
pause, disconnect, local-copy deletion, last-sync evidence, and recovery are
tracked separately in the [design acceptance ledger](android-health-screen-status.md).

## Verification

Version 0.1.7.31 (Android 1444) was cover-installed on Galaxy Tab Active3
(SM-T575, Android 13). This tablet supports Bluetooth LE but did not have
Health Connect installed. The visible overview-to-sources, file hub, manual
entry, and back routes were verified. The 47 focused device regressions passed
without skips. Fixtures used isolated databases; no health permission was
granted and no peripheral was paired. Android packaging reused the existing
native memory binary; its source and build configuration were unchanged.
