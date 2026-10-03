# Collaboration member state and connection recovery

## Scope

- Android 1.4.36 (1121); Desktop 1.4.7.
- A member's current status is distinct from historical execution attempts.
- Keep all stored messages, results, task IDs, checkpoints, and failure records.
- Do not restart the original protein research, grant tools, change acceptance
  criteria, disable the remote execution watchdog, or declare research complete.

## Changes

The collaboration transcript projects one current status per stable person ID
and conversation. Superseded attempt statuses and their loaded tool observations
move into the current member's process disclosure. Results remain append-only.
Late activity cannot promote an old attempt, identical names/providers cannot
merge distinct members, and a parallel result cannot hide still-running work in
the same team run. This is a presentation change, not deletion or database migration.

A provider circuit opening before dispatch now enters the existing paced
connection wait. After dispatch, local endpoint status is checked at most once
per 30 seconds (no extra MQTT heartbeat). Loss of connectivity writes a distinct
waiting state and releases the scheduler permit during the wait. Reconnection
checks the original managed task identity through the existing authenticated,
rate-limited result-recovery path; it never calls startRun again. An authenticated
recovery observation, fresh progress, or a terminal reply replaces the waiting
display. A display-write failure cannot block result recovery. Confirmed execution errors,
pause, stop, and completed results keep their meanings.

Desktop recall publish rejection reports an undelivered request with unconfirmed
phone connectivity instead of asserting the phone is offline or powered off.

## Verification

- Final Android regression: 719 tests, 57 suites, no failures/errors.
- Current-member projection: 19 tests passed; connection recovery: 5 tests passed.
- Debug APK and instrumentation APK assembled successfully (1.4.36 / 1121).
- Unchanged native memory rebuild was skipped; bundled-runtime checks passed.
- Desktop recall bridge: 12 tests passed.
- Desktop npm check: 68 tests passed; structure gate passed.
- Collaboration equal-budget contracts: 26 tests passed.
- Kotlin source-size and whitespace checks passed.

The new connection tests inject endpoint outages, temporary circuits, and
terminal events without invoking paid models. They cover original-task recovery,
no redispatch/cancellation on a transient outage, explicit stop, real execution
failure, and independent work with a single scheduler permit.

A device test seeds 22 historical failures and a current member, checks the
collapsed/expanded UI, reconnect state, final result, and Activity recreation,
then removes only its synthetic conversation. It does not toggle real networking
or rerun real research. The device test has compiled but has not run. Installation
awaits confirmation; neither the phone App nor the running Desktop was replaced.

## Boundaries

This does not turn confirmed Codex task timeouts into successful results. It does
not establish that a remote model's upstream internet connection is healthy from
MQTT connectivity alone. Historical results and failures remain auditable; the
loaded transcript window determines the available process history. A long real
outage and the production research's scientific completion are separate acceptance
tasks, not claimed by these synthetic tests.
