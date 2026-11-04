# Original ZIP Export History And Verified Saves

The Data and Files hub and the original library open a dedicated original ZIP
export history. The list uses an indexed 30-row keyset page ordered by creation
time and ID. Unsubmitted selection drafts are not history items. Each task
shows its frozen scope, time and result and can reopen the original manifest
without changing the current library selection.

Generating, sharing and saving remain distinct. The system Create Document
result is bound to the artifact attempt for which it was requested. An
explicit save writes the encrypted private ZIP's authenticated bytes to the
chosen destination and reopens that destination to verify its byte length and
SHA-256. The save receipt is written only after verification. On write or
verification failure the app keeps the private ZIP for retry and makes a
best-effort cleanup of the newly written destination.

Save attempts and receipts are encrypted inside the existing task snapshot.
After an interruption, an unfinished save is visible and can be retried with
a new destination; it is not assumed successful or automatically repeated.
No destination URI is retained for unattended access or cleanup. A later
failed save does not erase an earlier verified receipt. Previous-version
saved tasks remain visible as unverified, and a verified receipt remains
readable even if the private ZIP is no longer available.

## Recorded Acceptance

Android 0.1.7.55 / 1468 was built and cover-installed on Galaxy Tab Active3
(SM-T575) without clearing data. All 92 focused device tests passed without
skips across the final UI, export/migration, and backup runs.

- The native history test advanced to page two, recreated the activity,
  reopened the older task, and exercised both cancel and success with an
  intercepted Android Create Document result and an isolated FileProvider
  destination. It checked the saved bytes and reopened the verified receipt
  after removing the test's private ZIP.
- Store tests covered indexed paging with equal timestamps, standalone and
  shared schema upgrades, truncated destination readback, interrupted and
  stale attempts, retry, and preservation of an earlier verified save.
- The initial UI run exposed a one-shot activity-monitor issue in the test
  driver. The corrected test attaches a fresh monitor to each navigation.

The save tests do not claim a physical reboot during a write or a matrix
of third-party document providers. Test artifacts and rows were isolated
from the owner's archive.
