# Startup Local Recovery Order

iOS follow-up found while checking the Android #3007 execution/recovery audit
and the remaining parallel-result recovery path. Main baseline:
c6bad3465c673dfb2dcecb23b095185c129c7447. This is a concrete startup ordering
repair, not completion of the general Android liveness/recovery backlog.

The root view formerly awaited interrupted planning recovery before scanning
interrupted local nodes. Planning recovery can call applyLocalNativeActions and
start parallel/native work; the subsequent node sweep could then classify those
new current-process executing tasks as interrupted and pause them.

The root now uses the existing startup sequence type to order local stages:
cancelled-task reconciliation, cloud reconciliation, old-node scanning, then
planning recovery. The old-node sweep is synchronous and completes before the
planning stage may yield or dispatch. Cancellation before or between stages stops
later stages and retains only completed-stage counts. The outer run-recovery
sequence and completion callback remain unchanged.

No dispatcher, journal claim, result replay, planner prompt, task ownership,
permission, consent or provider policy changes. In particular, this does not
make a stale process marker proof that a tool is running, add automatic replay,
or implement immediate same-process reprojection of a rejected parallel result.
Already-running effects are not cancelled by this ordering change. General
recovery storage/fault handling and cross-process atomicity remain unverified.

Four Swift fixtures are authored in the existing registered policy test file,
not executed: exact ordering/counts, newly dispatched simulated work escaping the
old-node sweep, pre-cancelled recovery, and cancellation at each synchronous
boundary. The existing outer startup success/failure fixture remains unchanged.
No fixture invokes a real planning model, native tool or device.

Only JS/source, project-structure and whitespace checks are included. No Swift
build, XCTest execution, native/live provider, simulator/device, full repository
check, CI inspection, IPA generation or remote approval/merge is performed.
