# Android Health protected PDF recovery

The import queue records protected PDF recognition and page checkpoints in
the encrypted job store. WorkManager cannot start or retry a password-bound
recognition. A live foreground reader owns a nonblocking lock scoped to the
original store. Startup or opening the queue can recover an abandoned run
only after that lock has been released. The recovered row shows how many
pages were saved and waits for the user to unlock the PDF again.

The page and its checkpoint commit in one transaction. Resuming opens the
same protected original, checks the supplied password and extraction
permission, and continues after the last saved page. Partial protected
results are not shown in review or added to measurements. Neither the
password nor a decrypted document is written to disk.

The instrumentation fixture uses a separate debug-only process and an
isolated two-page synthetic report. It checks the live lock, terminates the
reader after the first page commit, opens the native queue, enters the
password again, and verifies unchanged first-page evidence, a single second
page, and byte-exact original retention. It does not stop the main app,
reboot the device, or open a personal report.
