# Android #4284: consent-scoped Health assessment notifications

Source: https://github.com/galaxyssi/GalaxySSI/pull/4284
Foundation: iOS #4372 / Android #4283.

## Production mapping

- Successful structured-review completion admits the attention receipt in the
  same atomic, profile-bound encrypted Health archive write as the final answer,
  completed job and checkpoint. Assessment storage alone cannot admit a receipt.
  Old completed reviews are not backfilled. A new non-attention review invalidates
  a prior concern notification without deleting assessment/message history.
- There is one receipt and one opaque stable notification identifier per concern
  and profile. The turn token distinguishes replacement assessments. Compare-and-set
  completion prevents a late callback from acknowledging a newer receipt.
- Delivery rechecks current source/record revision, completed job, exact concern
  and conversation, standing authorization, profile/local/online permissions and
  current cloud credential/configuration or paired Desktop model binding. Blocked
  destinations, removed contacts and replaced keys cannot authorize notification
  delivery. Destination policy changes wake reconciliation immediately.
- Global Health notification opt-in remains off by default. A separately saved
  Agent-assessment toggle defaults on, matching Android migration semantics, but
  never bypasses the global toggle or OS permission. Disabling or re-enabling
  delivery consumes old waiting receipts as in-app-only, preventing backlog bursts.
- Shared Health quiet hours and pauses defer receipts for later revalidation.
  Notification publication failures persist a 60-second retry deadline. Processing
  is bounded to 30 waiting receipts per pass, with further pages retained.
- Exact profile/conversation visibility suppresses both publication and foreground
  presentation. Multiple health views have independent visibility leases, cleared
  on disappear, background, profile and protected-data boundaries. Ordinary Agent
  conversations do not suppress unrelated Health updates or acquire Health prompts.
- The notification always uses generic localized text. It contains no measurement,
  model summary, rationale or attention reason, and no clinical urgency/sound/badge.
  iOS lock-screen preview controls remain OS-owned; the app does not offer a fake
  per-notification Android visibility switch.
- Taps carry only the opaque identifier and exact turn token. The existing private
  Health discussion opens only after fresh ownership, concern/conversation,
  authorization, destination and preference checks. Stale tokens cannot redirect
  to a newer assessment on the same identifier.
- Reconciliation recognizes an already-present matching OS notification after
  interruption instead of posting again. Terminal posted/in-app-only/stale receipts
  do not re-enter the queue after dismissal or re-enable.

## iOS Scheduling

Foreground/lifecycle reconciliation is connected to the app root without changing
its Agent layout. A registered `BGAppRefreshTask` also reads only encrypted persisted
profile/model metadata and the protected Health archive; it does not instantiate
the full chat runtime, invoke a provider, or perform research in the background.
The identifier is declared in both Xcode configurations; the existing fetch mode
is reused. Expiration cancels work, with durable receipts retained.

Quiet-window/paused notifications are not pre-submitted to iOS for future delivery:
their sensitive authorization/source state must be checked at the actual processing
opportunity. Foreground deadlines and OS-granted background refresh resume the queue.
iOS decides background execution timing; precise delivery while suspended/force-quit
is not promised. Protected-data unavailability defers processing. Generic existing
notices are withdrawn when quiet hours begin at the next execution opportunity.

As on Android, OS publication and local persistence cannot be one atomic transaction.
A crash after successful OS publication followed by dismissal before receipt commit
leaves a small replay window; visible-notification reconciliation reduces it but
does not claim exactly-once presentation or proof of human reading.

## Verification and Boundaries

Focused XCTest source covers encrypted admission/completion, no-attention and
missing-assessment cases, reopen/dismissal recovery, disabled/denied delivery,
quiet/pause deferral, durable retry, post-callback revocation, exact visibility,
credential/blocklist changes, stale source cancellation, safe notification/tap
payloads, replacement compare-and-set, 30/30/5 bounded pages, legacy defaults,
no migration backfill, and unavailable encryption keys preserving prior state.

Windows verification is limited to iOS structure, changed Swift grammar,
localization-source and diff/merge checks. XCTest, Swift type checking, actual
UNUserNotificationCenter delivery, BGTask scheduling and device UI are not claimed
as executed. This change does not build an IPA or introduce clinical alarms,
diagnoses, target/medication changes, care scheduling or concern closure.
