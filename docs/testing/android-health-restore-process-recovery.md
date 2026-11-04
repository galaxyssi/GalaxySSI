# Android health restore process recovery

A restore batch now owns a cross-process file lock from preparation through
preview, commit and disposal. The pending entry holds only a random batch ID.
Startup reconciliation skips a locked batch and never resumes or auto-commits
it. For an abandoned batch, the database receipt is authoritative: keep
committed original ciphertext, discard temporary review rows, and remove
uncommitted ciphertext. Failed cleanup keeps the entry available for retry.
Older unmarked folders remain eligible for recovery.

The debug-only fixture pauses at a verified backup preview so the device
test can attempt cleanup from the main process. The fixture then kills only
its own process at one of three points: preview, immediately before the
database commit after all writes, or immediately after commit before normal
disposal. The tests reopen the target store, reconcile staging twice, verify
receipts and original bytes, and retry the backup to check deduplication.
No actual health data or external provider is involved. Physical reboot
and sudden power loss are not tested by this fixture.

On Tab Active3 (SM-T575) with 0.1.7.65, all 29 backup/restore tests and
72 original-library, crop recovery and record-export regressions passed
without skips.
