# Android health crop restart recovery

Before a crop writes any image data, it creates and synchronizes a pending
entry identified only by a random operation ID. The staging and final files
remain encrypted. The final file is atomically renamed and its directory is
synchronized before the original and replacement page transaction commits.

Startup reconciles the dedicated pending directory, not the original library.
It removes incomplete staging and unreferenced encrypted outputs. A final
file still referenced by the authenticated original metadata is kept.
A shared file lock prevents cleanup from racing a live crop. A failed
cleanup leaves the pending entry for a subsequent pass.

The debug-only acceptance service stops its own isolated process during
encrypted staging or after rename but before database commit. The test
reopens the fixture and verifies the old page, exact original bytes and
orphan cleanup. A third test stops the fixture after commit with a recreated
pending marker to verify that the new page and verified ciphertext survive.
The four focused tests passed on the physical Tab Active3 (SM-T575) on
0.1.7.62, including a live-writer lock and an untracked-file preservation
check. No test opens the camera or touches personal health data. A full
device reboot or power interruption was not exercised.
