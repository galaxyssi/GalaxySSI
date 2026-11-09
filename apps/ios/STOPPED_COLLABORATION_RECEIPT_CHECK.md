# Stopped collaboration receipt check

`testStoppedPilotReconcilesOnlyItsOriginalDesktopReceiptAfterReopen` covers
the iOS receipt-only counterpart of Android #3444. It uses isolated SQLite
stores and a synthetic Desktop reply, not the app's live stores or an actual
MQTT session.

The fixture pins the original report hash and reopens the stopped checkpoint.
It issues only a result-page request for the original dispatch. It rejects a
foreign generation and confirmation, then commits the matched result and
confirms its receipt across reopen. The original report and STOP checkpoint,
other pending owners, and the explicit conversation selection must not change.
An empty pending list is not a successful pilot verdict.
