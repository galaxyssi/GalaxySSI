# Android Health Data and Files dashboard

The h25 dashboard is the local entry point for confirmed measurements and
original files. Its import and export buttons distinguish measurements from
originals. The task group opens existing import and export histories, while
backup creation, verification, history and restore keep their existing consent
and destination flows. Opening the dashboard never creates or shares an export.

Recent files are limited to four archived items, ordered by import time and ID.
Each opens the exact original and distinguishes a current measurement link, an
unlinked file and unavailable original bytes. The camera and upload totals
count archive entries, not copies on disk; a missing file can still have an
archive entry. Derived crops and review-only originals are excluded from those
two totals. The first render does not wait for the totals: encrypted original
metadata is scanned in cancellable keyset pages of at most 30, off the UI thread.
No original file contents are read for these totals. The activity discards
filenames and counts when stopped and stores only the scroll offset for return.

## Device verification

On the Samsung Galaxy Tab Active3 (SM-T575), use the instrumented
`HealthDataFilesDeviceTest` with isolated records and original storage. It
covers cross-page counts, ordering, cancellation, review/crop exclusions,
linked/unlinked/missing files, exact file detail, active updates, background
clearing, scroll restoration, and the import/export/backup routes. Pass
`-e dataFilesScreenshot true` to capture the populated dashboard and recent
files using synthetic data. The regression suite also includes original storage,
original library and export history, measurement exports, backup, restore and
Record Center navigation.
