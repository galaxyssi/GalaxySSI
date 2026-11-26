# Active native connector observation wakes

Android #3119 follow-up from main
`8a794e82ebe8f09790e41139295ffb7ac1ee9701`.

## Actual connection

Android `MainActivityConnectorTimeoutRecovery` defers timeout handling for owned
Desktop tasks, observes the original request and schedules another bounded check.
iOS had passive recovery sweeps and timing helpers but did not attach a deadline
wake to a saved native connector wait. This follow-up installs that connection
after a durable waiting-task commit, during foreground/restart restoration and
after a committed advancing remote status observation.

One token-fenced MainActor task per profile/owner/numeric source sleeps until the
existing accepted/running/read-only-stale timing boundary. Attachment deadlines
and the existing recovery probe interval are reused. A changed stage/anchor
replaces the old wake. The callback re-reads its owner and clock after sleeping;
stale timers cannot remove a replacement job or query using an old receipt.
No full task-store polling loop, mandatory catalog relocation or OS background
timer guarantee is added. At most 200 wake jobs are retained, matching the current
native restore-page bound; existing passive recovery remains available.

## Scope and safety

Only exact saved native Desktop waits qualify: current profile/permission,
unlocked foreground, permitted execution mode, non-private active session,
not tracking-paused/merged/cancelled, current action/result owner, pending managed
source/contact/conversation/turn/task/generation and verified Desktop endpoint.
Pause/background/policy changes stop the active wake; existing foreground restore
can install it again. Local/cloud jobs do not acquire a fabricated remote API.

At due time, require the original registered task identity and one current paired
route, track its exact managed binding, and wake the EXISTING recovery sweep.
The journal pump or legacy query path retains transport ownership, readiness,
authentication, query limits and result handling. The wake does not publish
directly, claim a second external execution, release ownership, synthesize failure,
cancel a provider, discover a replacement route or call the timeout-failure helper.
Publication at the precise deadline is not guaranteed when offline or queued.

Legacy local receipts could say remote queued without a status sequence. For
query scheduling only, treat that as unaccepted. A legacy authenticated sequenced
status without an acceptance timestamp can use its observation time as a read-time
anchor. These copies NEVER rewrite receipt metadata or authorize failure/replay.
New acceptance producers in separate #4593/#4594 retain their distinct scope.

## Verification limits

Eight XCTest methods are authored only, NOT executed: stage anchors, unchanged
acceptance clock on status metadata, read-only progress, attachment/probe bounds,
read-only legacy interpretation, terminal/user-wait exclusions, malformed/future
clocks and preserved unknown/manual/routing flags. Source checks freeze complete
coordinator code outside the declared lifecycle hooks and original query/timing/
catalog kernels. No Swift compile/typecheck, timer/concurrency execution, network,
restart/permission/device acceptance, CI watching or IPA.

This connects active scoped observation, not generic timeout failure/failover or
deferred candidate discovery. Those broader #3119 behaviors and native acceptance
remain incomplete. Android #3007 moves catalog PREWARM between background queues;
iOS mandatory runtime installation is different and remains unchanged here.
