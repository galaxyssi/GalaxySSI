# Android health Bluetooth device history

The Devices & Data Sources page can expand a paged list of identifiable
Bluetooth blood pressure sources with saved measurements. Rows use the
existing pseudonymous source key, not the visible device name. Measurement
time and receipt time come from the latest saved measurement for that
source. This is historical data, not pairing, current connection, battery,
or compatibility status.

The inventory uses the indexed group cursor and reads at most one record
per displayed group. Opening a row uses the same source filter in the
paged records screen; it does not scan, connect, or write measurements.
Records without a reliable historical group are not assigned to a device
by name. They remain available in the unfiltered catalog.

The list is subject to the existing confirmed-metrics privacy permission.
It clears labels and timestamps when hidden or when permission changes.
Only the expanded state and opaque page cursors are restored after
navigation or activity recreation.

On Tab Active3 (SM-T575), Android 0.1.7.73 passed all 64 focused
instrumentation tests with no skips. The new cases verified a 34-source
inventory across two pages, separate rows for two same-name sources,
the matching device history, different measurement and receipt times,
recreation, and privacy revocation. Tests used isolated synthetic
measurements; no commercial monitor was scanned or paired.
