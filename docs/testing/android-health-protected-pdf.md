# Protected Health PDF Import

A password-protected report is archived as its original bytes using the
existing authenticated encrypted-original store. The file queue distinguishes
password required, incorrect password, extraction denied, and interrupted
recognition. These jobs never re-enter unattended WorkManager recovery.

Unlock runs locally while the capture activity is visible. A correct password
opens the protected bytes through the existing seekable authenticated channel.
The PDF library uses memory-only scratch storage. The app does not create a
decrypted PDF file, send document contents to a provider, or save the password
in a database, intent, task, or activity state. The app clears its password
character arrays after opening the document; the parser API requires a transient
managed string and does not provide guaranteed memory zeroization.

Visible text uses the existing text-and-coordinate checks. Scanned pages fall
back to local OCR over a bounded page raster. Recognition commits encrypted
checkpoints per page; after cancellation, backgrounding, or process loss, the
user must re-enter the password to resume. Extract permissions are honored
independently of password correctness. No measurements are saved until the user
confirms them in review.

The original viewer can unlock and navigate protected pages without changing
the archived file. The recognition evidence viewer can unlock the selected
page independently. Leaving the capture activity closes the preview and drops
the decrypted view. Exporting the original exports the same password-protected
bytes, not the unlocked representation.

## Recorded Acceptance

Android 0.1.7.52 / 1465 was built and cover-installed on Samsung Galaxy Tab
Active3 (SM-T575). All 47 focused device tests passed, with no skips. The
native queue case verified cancel, background dismissal, incorrect password,
successful review, and reopening the protected original. The pipeline cases
verified AES-128 mixed text/OCR resume, AES-256 permissions, and byte-exact
original recovery. Existing PDF text, review source, import UI, structured
preview, original storage, and report-reminder tests also passed.

The tests used isolated databases and synthetic documents. This does not
establish interoperability with every PDF encryption handler, a full Android
version matrix, or a complete 32-screen acceptance run.
