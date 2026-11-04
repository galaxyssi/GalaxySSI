# Android Bluetooth Blood Pressure

The Devices and Data Sources page opens a foreground collector for monitors
advertising the standard Bluetooth Blood Pressure Service (`0x1810`).
Discovery does not prove that a monitor is compatible: the GATT connection
must discover the Blood Pressure Measurement characteristic (`0x2A35`), its
indication property, and a successful client configuration write. Pairing is
an explicit option; merely bonding does not create a measurement.

- The collector processes the signed decimal SFLOAT format, pressure unit,
  optional device clock, pulse, user slot, and device status flags. It
  rejects truncated measurements and missing or non-finite pressure
  components. The unsupported mean-pressure component is not stored.
- Receipt time is captured at the indication callback. The device clock
  is interpreted in the phone's local zone only when the time is valid,
  unambiguous, and not in the future. Otherwise the record uses receipt time
  and retains any interpretable original clock separately.
- A new device and slot must be explicitly confirmed as the user's own.
  Automatic saving is opt-in and applies only to the same bonded device
  and slot, during an active measurement, with a recent usable clock and no
  reported status flags. Unknown user slots always require review.
  Conditions default to unspecified for automatic saves.
- The device identity and deduplication index use keyed tokens. The
  authenticated, encrypted observation stores the label, device time,
  receipt time, and measurement. A timed retransmission cannot create a
  second record, overwrite an edit, or restore a deleted record. Untimed
  frames have no cross-connection event identifier and require manual review;
  their duplicates are suppressed only within the explicit capture.
- Pause stops local ingestion without closing the link. Disconnect ends
  the link without deleting saved measurements. Leaving the screen releases
  scan, GATT and pairing resources and clears any unsaved readings.

The first adapter does not implement proprietary watches, Enhanced Blood
Pressure Measurement, stored record access, background monitoring, or
vendor-cloud sync. Individual commercial device compatibility and actual
pairing behavior must be checked separately.

Protocol: [Bluetooth SIG Blood Pressure Service](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/BLS_v1.1.1/out/en/index-en.html).

## Radio Verification

On Windows with a BLE peripheral-role adapter, run
`tools/dev/test-health-bluetooth-fixture.ps1` with Windows PowerShell 5.1.
It exposes only a synthetic measurement and stops advertising on completion
or timeout. Run `HealthBluetoothRadioDeviceTest` on an Android 12+ test
device with the fixture's Bluetooth address as `bleFixtureAddress`, and
optionally its exact advertised name as `bleFixtureName`. Instrumentation
delegates scan/connect permissions only for the test, matches the supplied
fixture, and never writes the readings into the health archive.

Version 0.1.7.33 (1446) was cover-installed on Galaxy Tab Active3. The
visible idle page, five protocol JVM tests, and 113 focused device tests
passed. The production GATT collector independently passed a real BLE
fixture test for discovery, subscription, indicated values, and pause.
No fixture record was saved into the user's archive and the production
package kept its original ungranted Nearby Device permissions. This does
not establish compatibility with a commercial monitor or verify the
system pairing prompt and bonded-device autosave end to end.
