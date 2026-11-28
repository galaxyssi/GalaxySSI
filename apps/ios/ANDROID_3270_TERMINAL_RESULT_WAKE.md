# Native Terminal Result Recovery Wake

Reference: Android #3270, 0e709fbbc84d8fc5bca82b854e248066098badbd,
AgentRemoteSilencePolicy and AndroidAgentRemoteSilence. Independent iOS base:
c6bad3465c673dfb2dcecb23b095185c129c7447. Existing iOS #3663/#3664/#3666-3668
already cover other reply recovery work; this is a distinct missing native
active-wake path, not their duplicate or full Android parity.

## Actual Missing Path

The existing native active timer stops on terminal status metadata. A remote
completed/failed/timed_out/cancelled observation is not a committed result. The
managed response may remain pending while result pages, manifests or delivery
are recovered. Android keeps probing the original source and bounds terminal
result delivery at fifteen minutes; iOS previously relied on passive sweeps.

Retain the existing stage clock and timer unchanged for nonterminal work. When
no stage wake exists, resolve the original registered identity and one current
paired route, require the current profile's recovery journal, and match the
exact pending managed run/source/contact/conversation/turn/task/generation.
Only a durably recorded terminal observation matching the saved waiting result's
status/sequence/time may create the result wake. A text label alone cannot.
Team, goal-work and Codex replay sources do not acquire this native scope.

## Recovery Behavior

Wake the existing original status/result recovery sweep, not a new request
executor or direct publisher. Poll at the existing thirty-second interval and
retain the original fifteen-minute terminal anchor. Duplicate observations do
not grant a fresh delivery period. Near the boundary the delay may shorten;
expired records retain probe throttling so failed reads/checked projection cannot
create a zero-delay retry loop. Clock changes and offline queues can defer work;
this is not an exact wall-clock deadline or background-execution guarantee.

Foreground/unlocked, profile, task/session, permission and cancellation gates
remain in the existing context resolver, with re-reading after sleeping. Saved
final/accepted results stop this polling. Stage deadline observation from #4701
remains a separate optional feature and does not reclassify terminal result wakes.

No model/tool replay, fallback, remote cancellation, slot release, execution
grant, invented success/failure or terminal-delivery retirement is added. Existing
receipt/import/expiry projection owns actual outcomes. In particular, uncertainty
about a result does not prove that the original external action failed.

## Verification Limits

Ten synthetic Swift fixture methods describe stage compatibility, terminal
statuses, pacing, immutable expiry anchors, malformed/future clocks, exact
identity/generation, nonterminal/user waits, committed-result exclusion and
archive reopening. They are authored and registered, not compiled or executed.

Only JS/source, project structure and whitespace checks are included. No Swift
build, XCTest execution, native timer/network/storage fault, real result import,
device/simulator/live model, full repository check, CI inspection, IPA, private
evidence upload or remote approval/merge is performed. This does not implement
generic remote-silence failover or complete the broader iOS parity backlog.
