# Android health original retention

The Import Center retains original files by default. Turning retention off applies to the import routes opened from that screen, including each page in a camera batch. Explicitly archiving a file to the original library is a separate operation.

Review-only files use an isolated encrypted copy even when an archived file has the same hash. The copy remains readable during review and is removed after a confirmed measurement save, completed table save, or explicit discard. Unselected recognized drafts and the confirmed source link remain. A failed import can still be retried. After process death, recovery reads the pending review-only index and checks durable save or cancellation state before removing bytes.

Portable backups never copy review-only bytes. For a confirmed record without a retained source, the backup includes its source metadata without file contents. If the same hash is independently archived, the backup uses that retained source and maps the exported record link to it without changing the local record. Unconfirmed review-only sources are not exported.

## Verification

- `HealthOriginalStoreDeviceTest` checks encrypted copy isolation, camera-batch inheritance, discard, and idempotent recovery after durable confirmation.
- `HealthBackupDeviceTest` checks retained bytes, metadata-only sources, verified record links, and omission of unconfirmed sources.
- `HealthOverviewUiDeviceTest` checks the native switch defaults to on and preserves the user's choice during Activity recreation.
- Run the PDF, structured import, table, library export and restore suites on the same APK to check adjacent flows.
