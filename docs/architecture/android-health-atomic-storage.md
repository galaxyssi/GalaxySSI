# Android Health Atomic Storage

Schema 7 stores measurements, revision history, original metadata and their
import/capture/export rows in the same SQLite database. The encrypted
original bytes remain in the existing private file tree. The original storage
AAD and digest token namespace deliberately remain
`health_originals_v1.db`; changing the physical SQLite path must not change
the original ID, key, file path, deduplication token, or ciphertext.

Existing metadata is copied from the legacy database in foreign-key order.
Pre-v3 original schemas first use the existing legacy schema upgrade.
The copy reads the source from a stable transaction and writes only the target.
All rows and the migration marker commit together in the target database.
Concurrent opens recheck that marker inside the target writer transaction.
An interrupted migration retries without exposing partial rows. Existing
legacy data is retained for recovery, but no new originals are written there.
Fresh installs do not create a legacy database. Large old ciphertext fields
are read in slices to avoid the Android CursorWindow row limit.

This allows the [restore flow](android-health-restore.md) to prepare and
authenticate encrypted original files before opening a single-database
transaction, then publish their metadata, measurement revisions, and a
restore receipt together. A file staged before that commit is not a visible
original; the restore path checks receipts before clearing staging. No
multi-database WAL commit, temporary plaintext, or destructive replacement of
the existing profile is required. [SQLite WAL documentation](https://www.sqlite.org/wal.html)
explains why commits across attached WAL databases are not atomic as a set.

The standalone backup verifier still remains read-only.
