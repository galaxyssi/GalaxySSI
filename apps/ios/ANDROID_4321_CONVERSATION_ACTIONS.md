# Android #4321: conversation actions and local names

Source: https://github.com/galaxyssi/GalaxySSI/pull/4321

Android merge inspected: `3a5e2b786372ba583da181ba7a75665a8928dc26`.
Compared the anchored action menu, rename policy, action dispatch, in-place hub
updates, localized resources and regression scenarios. iOS-only follow-up.

## Interaction mapping

- Conversation rows use native iOS anchored context menus, with readable title,
  rename/remark and pin icons, and a separated destructive delete action. UIKit
  owns viewport placement, light/dark rendering and native menu dismissal.
  Existing Agent advanced actions remain in More Actions rather than disappearing.
- Both Agent rows and nondeleted contact conversation rows open the new explicit
  save/cancel editor. It receives the raw title/name separately from the decorated
  display title, plus row kind, stable ID, owner and contact fingerprint. A deleted
  or system contact has no remark editor. Directory-contact deletion is unchanged.
- Validation matches Android's normalized 72 UTF-16-code-unit, nonblank,
  single-line policy, rejecting C0/C1 controls and Unicode line/paragraph separators.
  The editor shows a count; unchanged names cannot produce duplicate writes.
  IME Done supports unchanged dismissal and invalid-name feedback.
- Saving is asynchronous, disables repeat submit/cancel while saving, and leaves
  failed input available for retry. Scene changes/dismissal clear editor text and
  cancel pending work; per-editor attempt IDs and row/owner checks reject stale UI
  completions. Already committed user-requested Agent metadata is not rolled back
  merely because the app backgrounds after its database commit.

## Persistence and concurrent changes

- Agent metadata renaming is an encrypted SQLite BEGIN IMMEDIATE transaction,
  checked against the current raw title and cancellation state. It reads the
  current row/draft under the existing lock and preserves every non-title field,
  including activity timestamps, status, model/context settings and counters.
  Database work runs on a detached worker; cache publication stays on MainActor.
  The synchronous rename entry now returns actual database failure, not a
  successful mutation wrapper that could hide a failed write.
- Contacts keep the existing encrypted root state, not an additional remark store.
  A worker owns only encrypted bytes, an immutable key/value snapshot and target
  metadata. Structured JSON patching and encryption preserve unknown/other root
  fields. MainActor compares the original encrypted bytes before committing; a
  concurrent whole-state save causes a bounded retry against fresh bytes instead
  of overwriting it. Missing/changed/deleted targets and owners fail safely.
  Only the small UserDefaults final commit/cache publication remains on MainActor.
- Synchronous contact renaming also validates names and reports save failure,
  restoring its previous in-memory contact when persistence fails. Device default
  names are remembered only after successful metadata persistence.
- No messages, conversations, model selections, trust credentials or remote peer
  profile are changed by a local rename. Existing delete confirmation is retained.

## In-place results

Keep a bounded unfiltered projection of the already loaded Agent window/contact
summaries. Name edits patch that projection and reapply the current search without
invalidating the whole hub or changing stable row IDs, offsets, page cursors,
unread/status decoration or activity ordering. Contact name-only updates no longer
restart the conversation-list task. Directory sorting still uses its normal
reload key. Snapshot adoption reconciles current cached titles so work prepared
before an edit cannot restore the old visible name. Background suspension releases
the new cached projections along with existing previews.

## Verification and limitations

XCTest source covers UTF-16/control validation, encrypted row/draft identity and
metadata preservation, stale/deleted targets, kind-safe row patches, search
projection, unknown root-field preservation, owner checks and concurrent-root CAS
rejection. No tests executed, per request.

Static checks only: `npm run check:ios`, modified/new Swift grammar parsing and
`git diff --check`. These are not Swift type checking. No Xcode build, simulator,
device menu/keyboard/scroll tests, native screenshots or IPA on Windows. Native
context-menu geometry/appearance, background dismissal and editor gestures still
require native validation; no pixel-identical Android rendering claim is made.
