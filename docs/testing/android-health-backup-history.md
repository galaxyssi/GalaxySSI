# Android portable backup history

Data and Files exposes a paged Backup History. The device-encrypted receipt retains the backup scope, timestamps, generation result, latest save outcome, and last verified save. It contains no password, owner name, record values, external URI, or share destination. The temporary encrypted package still expires after seven days or can be explicitly discarded without deleting the receipt.

The repository records generation before reading the snapshot. It stages the digest and size before publishing the private file; reopening an interrupted task verifies any published bytes before calling it ready. A save is verified only after the selected destination has been read back and matched byte for byte by size and digest. If process death prevents that verification, the history says interrupted and does not infer what the external provider retained. A failed later save does not erase the previous verified save.

Run `HealthBackupDeviceTest`, `HealthRestoreDeviceTest`, and the related export and retention suites. The history tests use isolated databases, encrypted fixture backups, controlled destination streams, and a native create-document result backed by an isolated content-provider file. Opening or discarding the history does not share or upload a file.
