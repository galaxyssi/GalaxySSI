# Browser View Ownership And Loss

Reference: Android #3525 head `822f73b8d01da5ef6ff950a360f6a1a03923d034`,
managed-browser control events. Baseline main `c6bad3465c673dfb2dcecb23b095185c129c7447`.
This is an iOS adaptation of original-handoff ownership, generation containment,
durable interruptions and no automatic human-handoff replay, not an Android host port.

Integration follow-up: project registrations now sit beside the browser dependency
and native-tool tests instead of shared insertion anchors. The dedicated guard uses
#4664's exact approved revocation/Store normalizers when present; all remaining
coordinator/Store comparisons and browser lifetime assertions are retained.

## Actual Gap

The prior iOS handoff was already encrypted and its return was durably committed.
Its host identity, however, covered the whole App process, not the actual WKWebView.
Closing/destroying a sheet or pausing its owner could discard the live page while
leaving the request awaiting user control in the same process. Reopening it could
load a new page under the old request without acknowledging the lost browser state.

## Production Connection

Both managed-member and supervised-plan browser views now require a saved view
lease before loading. The sealed managed record stores leases by call ID, bounded
by its existing 32-handoff limit. Supervised tasks store an optional lease with their
existing owned state commit. Exact ticket/plan/owner and control checks remain in
place. No new plaintext preference store, page content, model call or network probe
is added. Legacy records without a view lease remain decodable.

A process-local registry marks only successfully saved leases live and permits
only the same view instance to reuse one. A concurrent second sheet cannot load,
operate or close the owner's browser. Its own close button only dismisses itself.
Closing or deallocation releases only the matching in-memory lease; the persistent
marker remains until existing record cleanup. A subsequent claim or normal recovery
detects the missing live instance and commits `browser_view_closed` interruption.
Old-process requests are reconciled before load. New supervised requests clear the
old request's lease rather than inheriting another generation's authority.

Explicit Close commits the interruption before dismissal; failed persistence keeps
the view open for retry. Interactive swipe dismissal is disabled. Unexpected sheet
teardown attempts the same commit, then releases the view; if saving fails, the saved
lease still prevents a later fresh page load until interruption can be committed.
Existing startup/foreground/control recovery handles the durable event under its
original execution lease and owner. PAUSE/STOP semantics and delivery are unchanged.

Closing is NOT returned control, authentication, browser-state or business success.
The interruption requires fresh external observation and does not replay a browser
mutation. URL/DNS, cookie scoping, extraction, cancellation, model-loop journal,
permission and effect policies are retained. The registry is capped at 200 live views.

## Verification Limits

The dedicated JS guard pins the Android contract and freezes the complete coordinator
outside declared lifetime hooks, managed store outside explicit view-lease/reconcile
hooks, task models outside the optional lease, and all navigation/observation policies.
The existing capture guard retains its assertions through a declared browser-hook
normalizer. Eight synthetic XCTest methods are authored, not executed: failed save,
live/duplicate/lost/foreign claims, reopened encrypted records, paused recovery, stopped
and stale tickets, legacy task decoding and unverified close outputs.

Only JS/source/project and whitespace checks are run. No Swift/native compilation,
XCTest, WebKit/UI/device/process-kill/fault acceptance, full check, CI monitoring or IPA.
These checks do not establish cross-process CAS, fsync/power-loss durability, exact
cancellation timing or full Android browser feature parity. The overall backlog remains.
