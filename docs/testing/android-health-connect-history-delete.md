# Android Health Connect local history deletion

The Devices & Data Sources page and the authorization page open Local
Health Connect copies. Users select one supported data type and see the
stored measurement count and date range before confirming. Managing
these local copies does not require a connected provider, an OS read
grant, or consent to use the measurements for analysis.

Preview and erasure use bounded keyset pages. The erasure transaction
checks the metric version and the confirmed scope and authenticates the
record's source before removal. It removes app-owned copies, revisions,
edit drafts and source links for the selected data type, including
previously soft-deleted copies. Manual, Bluetooth, and other data types
are left untouched. A stale preview or failed transaction removes
nothing.

Health Connect permissions, source apps, sync settings and saved
checkpoints are unchanged, as are previously exported files and
backups. Records can be imported again later. The encrypted privacy log
stores the deletion purpose and scope, not measurement values. This is
logical removal from the app database, not a forensic storage wipe.

Android 0.1.7.75 passed 46 focused instrumentation tests on Tab Active3
(SM-T575), with no failures or skips. New cases verified native cancel,
stale preview rejection, local removal with analysis consent off, a
rollback after the first batch of a 34-record deletion, legacy Bluetooth
and manual record preservation, and unchanged sync checkpoints.
Tests used isolated synthetic measurements, not a live provider.
