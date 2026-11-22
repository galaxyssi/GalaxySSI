# Android #4309: remove Health Center reminder entry points

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4309

Android merge: `aa21826a20d23b931441bbd5a10816ff8c0bd160`.

Android removes its overview reminder bell/spacer and the combined Reminder Center
row from the functions menu, leaving scheduling, notifications and notification
entry points intact.

The iOS overview already has only a trailing functions menu and an inline centered
navigation title, with no reminder bell or balancing spacer. Its functions menu
instead exposed three separate reminder destinations: review, recording and sleep.
Remove those overview-menu shortcuts to align the visible surface with Android.

Keep the existing destination views, scheduling services, notification handlers
and preference records. Recording reminders remain reachable from Health Assistant,
review reminders remain reachable from care/visit flows, and existing notification
navigation continues unchanged. Do not delete or silently disable existing sleep
reminders simply because their overview shortcut is removed. Privacy, body, weekly
report and other non-reminder menu entries are unchanged.

This branch is independently based on main, with no Android/Desktop edits or app
version/IPA changes. Verification is a targeted source audit of the actual header
and menu plus project structure and Swift grammar checks, not a native screenshot
or device interaction test. No XCTest execution or Xcode build is claimed.
