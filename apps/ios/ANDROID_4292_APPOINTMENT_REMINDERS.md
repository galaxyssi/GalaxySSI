# Android #4292: confirmed appointment reminders

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4292
Android merge: `29332f5af8e4443969f5cb5006c37de614113fb0`.

## Implemented on iOS

- Visit details expose appointment reminder status, explicit confirmation, rescheduling,
  cancellation and a preparation entry for planned/booked visits.
- The editor uses the encounter's recorded time zone, validates strictly future times
  before the appointment, and requires explicit UTC-offset selection for ambiguous
  daylight-saving times after editing. Saving revalidates the current visit and stamp.
- An encrypted local follow-up slot per encounter stores an opaque rotating token,
  encounter revision, privacy permission epoch and appointment deadline. This does not
  adopt clinical actions, authorize research, or submit a model request.
- Notification opt-in, system permission, pause and quiet hours apply independently
  of daily recording and model-review enablement. With notifications disabled the
  reminder remains visible in-app. Quiet-hour deferral cannot cross the appointment.
- Editing, attendance, cancellation, deletion, concern pause/closure and local-care
  revocation invalidate affected reminders. Terminal cancellation/expiry persists;
  clock rollback or renewed permission does not revive the old token.
- Notifications have generic localized content and only a kind marker plus opaque
  identifier. Delivery/tap revalidate the exact current encounter. Foreground and
  opportunistic background reconciliation remove invalid/expired notifications;
  observed delivery is persisted to prevent reposting after dismissal.

## Verification and limits

Added XCTest source covers explicit confirmation and time bounds, token rotation,
stale cancellation/submission, independent encounters, edits/attendance/cancellation/
deletion, privacy renewal, notification opt-out, quiet/pause deadlines, persistent
expiry, exact-visit routing, generic content and non-reposting after delivery.

Windows cannot execute Xcode compilation, XCTest, iOS notification authorization or
real timed delivery. Static project and Swift grammar checks are not runtime proof.
Android's controlled callback tests likewise do not establish real reboot delivery.

iOS may deliver an already scheduled local notification late while the app has no
execution time. BGAppRefresh is opportunistic, not an exact deadline. The app checks
expiry when scheduling, presenting in foreground, opening and reconciling, but cannot
guarantee suppression at the OS's background firing time or after force-quit/reboot.
This PR does not claim that stronger behavior or real-device certification.
