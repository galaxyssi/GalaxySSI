# Android Health Backup Restore

The restore screen is separate from table/JSON import and from the read-only
backup verifier. It opens a user-selected document, prompts for its password,
and verifies version, owner, original hashes, measurement links and the
authenticated end of the archive before offering any live writes. A named
backup and a named local profile must match; all accepted restores require
explicit ownership confirmation. The only write target in this increment is
the current self profile.

## Review

Original bytes stream directly into app-encrypted, uniquely named private
files. Staged record and conflict rows are encrypted individually in a
temporary database. No original or record metadata becomes visible to the
live health views until commit. App cancellation or leaving the screen
discards uncommitted staging; startup cleanup removes abandoned batch
directories only when their live database receipt does not exist.

The preview distinguishes new records, equivalent existing records, and
conflicts. Conflicts have a paged detail view with the backup and local
values, including differing notes. Existing and deleted record IDs are
preserved. Missing originals are explicit and require confirmation. A known
missing original may be repaired from verified bytes without changing its
local ID; identical intact originals are reused. Incoming references are
remapped by verified digest when needed.

## Commit

The original staging files and their directory entries are synchronized
before the SQLite write transaction. Selected metadata and record revisions,
metric-version clocks, and the encrypted restore receipt are committed in
the same database transaction. If the observed local data or profile changes
after the preview, the previous plan cannot be committed. A late write
failure leaves no partial live observations, originals, or receipt. The
receipt records the package ID, date range, result counts and time; reopening
the same package does not duplicate restored records.

The restore operation does not overwrite conflicted measurements or
resurrect records deleted on this device. Import into a separate profile,
explicitly applying a conflicting replacement, historical revision export,
and live-provider identity reconciliation are not covered by this increment.
