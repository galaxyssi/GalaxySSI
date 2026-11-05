# Android measurement deletion and undo

The measurement detail page distinguishes an individual removal from
the permanent local erasure action in Privacy & Data. Removal hides the
record from current results and keeps its encrypted history. The same
detail page offers Undo deletion until the user navigates away; page
recreation retains only the existing route identity and deletion revision.

Undo checks the exact deletion revision, keeps the measurement ID,
measurement time, source and fields, and appends an encrypted revision.
Secondary links are authenticated and re-encrypted for the new revision.
The transaction updates the metric version so version-pinned results
can detect the change. A newer matching measurement, a conflicting
source claim, or permanent local erasure cannot be bypassed by undo.

Android 0.1.7.79 passed the native Tab Active3 (SM-T575) workflow:
choose a past date and time, save one blood pressure observation, edit
it, cancel removal, remove it, recreate the page, and undo. The test
asserts the original date, measurement ID, components, edited note,
and four revisions. Isolated store tests verify rejection after permanent
erasure, duplicate and stale rejection, preservation of secondary evidence
and a transaction rollback on an OCR source conflict.
