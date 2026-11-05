# Share Completed Health Exports

Record-only CSV/XLSX/JSON, records-and-originals ZIP and original-only ZIP
exports have independent Save and Share actions. The Share action warns that
the chosen app can retain a copy of the unencrypted export, then opens the
Android chooser without selecting a destination. Dismissing either dialog
does not mark an export saved or delivered.

The private export remains encrypted. An exact, temporary read-only URI grant
exposes the completed attempt through an authenticated seekable descriptor.
No plaintext staging file, prefix grant, or persistable grant is created.
Only the current completed attempt can be opened; the provider does not expose
filesystem paths, source database rows, or unfinished attempts. Ciphertext
authentication failures fail the corresponding read rather than substituting
missing bytes. The recipient's ability to keep its own copy is outside the
app's control.

The password-protected backup share route stays independent. Verification
uses only synthetic fixtures, never an external recipient or real health data.

## Recorded Acceptance

Android 0.1.7.54 / 1467 was cover-installed on Galaxy Tab Active3 (SM-T575),
keeping existing data. All 68 focused device tests passed across two final
runs, with no skips. The native test opened and dismissed the actual system
chooser without selecting a recipient or recording a save. A separate Android
shell UID could read the exact file only during an explicit test grant. The
tests also checked wrong attempts, in-progress exports, metadata, write denial,
ZIP seeks across encrypted segments, and tamper rejection.

The first UI test run contained two test-driver failures: shell error output
was not captured, and the chooser assertion matched historical activities.
The final run checks URI permissions directly and uses resumed activity only.
An external app delivery matrix and a multi-device SAF matrix are not claimed.
