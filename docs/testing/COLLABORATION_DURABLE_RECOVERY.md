# Collaboration Durable Recovery

## Failure addressed

A local `agent-team:` parent was incorrectly monitored as a Desktop contact. After the ordinary silence timeout, its workspace and delivery became terminal even though its members continued running. The team then marked its final result delivered before the canonical conversation response was committed. This could leave a failed conversation with a successful member result visible underneath it.

## Contract

- Local team parents never enter the Desktop silence watchdog.
- Historical repair requires an exact team, conversation, turn, task, source and contact match, the known silence error, and the original saved distributed wait. Cancellation, unrelated failures and successor deliveries remain protected.
- Completion is acknowledged by a canonical assistant transcript commit, not by publishing to the response bus. Uncommitted results are reconciled on startup and periodically in the process.
- Managed member responses retain their body until the team checkpoint acknowledges them. Transport receipt alone is insufficient.
- An interrupted DAG can resume queued stages after all previously running stages have produced their original results. Terminal stages provide their saved dependency evidence and are never executed again.
- An unresolved in-flight stage is queried through the existing authenticated result recovery path. It is not blindly re-dispatched. If the remote executor permanently loses its result, automatic replay is not considered safe.
- Offline or capacity waits use bounded exponential backoff without a maximum attempt count. Waiting yields the local execution permit so other members can progress.
- Pause and stop are durable user controls, separate from network failure. Pause prevents new dispatches; an already dispatched remote step may finish. Stop is not automatically resumed. Starting a new research round is distinct from replaying a stopped run.
- Stopping scheduling does not claim immediate remote cancellation. Exact owned Desktop steps retain their response ledger and retry the existing authenticated cancellation command, at most once per minute while connected, until a terminal response arrives. An offline Desktop cannot confirm cancellation immediately.
- Follow-up after delivery uses a new turn and run identity, carrying a bounded excerpt of the preceding goal/result and retaining the archive for full-source recall. Current user instructions take precedence over historical findings.

## Android lifecycle limits

The recovery loop is owned by the process runtime rather than an Activity. Existing Android background startup and result recovery workers restore persisted state when the OS allows execution. A user force-stop prevents Android background execution until the app is explicitly opened again. Reboot/Doze scheduling is not an unconditional always-running guarantee.

Managed member replies also enqueue a coalesced background recovery worker. This initializes the process-owned team controller even when no Activity or ordinary final-response worker has been started.

## Verification

Targeted JVM coverage includes checkpoint reuse, unresolved remote work, cancellation protection, identity mismatch, bounded retry pacing, permit release, offline recovery and durable response acknowledgement.

`AgentTeamDurableRecoveryDeviceTest` uses isolated encrypted fixtures. Its selected-team repair test is opt-in through `selected_team_run` and never re-executes models. Existing `AgentTeamProcessDeathDeviceTest` separately checks late results across real process recreation.

### Verified on 2026-10-01

- Android v1.4.9 (1094) was built and installed over the existing S26U installation without clearing user data.
- 79 targeted JVM tests passed across collaboration, subagent execution, response retention, remote silence, team messaging and recovery policies.
- All five `AgentTeamDurableRecoveryDeviceTest` cases passed, including repairing the selected real conversation. Its 19 completed member stages retained their original completion times; no model task was executed again.
- The process-death seed/recover test passed with distinct process IDs (20718 and 20930). It recorded a successful team, exactly one final response, zero fixture replies left unapplied, zero ordinary-chat leaks, and duplicate suppression.
- The process-death fixture now persists a unique identity for each two-phase test. Reusing an old acknowledged identity is intentionally rejected by production deduplication and is not a valid new acceptance run.
- Screenshots confirmed that the selected conversation list row shows the saved final summary rather than an execution error.
- Kotlin source-size and whitespace checks passed. The repository-wide `npm run check` remains blocked by existing i18n text-policy findings outside this change.

### Follow-up verification on 2026-10-02

- PR #3313 contains the v1.4.9 baseline above. The v1.4.10 (1095) follow-up is isolated on `test/collaboration-recovery-fault-matrix-20261002` and was not installed for this reboot test.
- 108 targeted JVM tests passed with zero failures or errors. New fault injection exposed a dispatch race when pause or stop arrived during a connection check; both regression tests failed before the fix and passed after rechecking control state immediately before dispatch.
- A transient connection failure test verified one retry and exactly one model dispatch. Long-offline retention tests verified that pending correlation survives 90 simulated days and an unapplied result body survives one simulated year. These are clock-based unit tests, not elapsed-time endurance claims.
- The response retention follow-up expires only applied history. Pending and completed-but-unapplied records cannot be discarded solely because seven days elapsed.
- S26U underwent a real authorized reboot with the installed v1.4.9 build: the boot counter increased from 14 to 15. After user unlock, the test injected isolated late replies through `MessageService` and recovered the checkpoint written before reboot.
- The reboot fixture report recorded seed PID 22392, recovery PID 14938, a successful team, exactly one final response, zero unapplied fixture replies, zero ordinary-chat leaks and duplicate suppression. Only test-owned records were cleaned up.
- The application process existed before recovery instrumentation started. This observation does not independently certify unattended boot scheduling: instrumentation explicitly triggered the late-reply phase after unlock.
- Desktop scheduling remained at zero active and zero pending tasks, with the same latest completed task before and after the test. No original research or new model request was dispatched.

Production provider/MQTT outages, unattended Doze/boot recovery, real Desktop stop acknowledgement, permanent server-state loss and elapsed multi-day waiting still require a broader endurance matrix. Passing a checkpoint fixture does not certify all of these conditions. The execution-store 200-run retention bound also requires a separate unresolved-run retention review before claiming arbitrarily long, high-volume operation.

## Repeatable network and Doze acceptance

Install the application and instrumentation APKs built from the same checkout, then run:

```powershell
$env:ADB = 'C:\path\to\adb.exe'
node tools/dev/test-android-team-network-recovery.js --serial DEVICE_SERIAL --port 5037 --outage-seconds 600 --doze-seconds 180
```

This is an explicitly selected, disruptive device test. It disables Wi-Fi and mobile data, simulates unplugging, sends the selected device to the home screen and deep idle, then restores the original network settings and real battery state. Do not run it while the device is needed for other network-dependent work. It refuses an existing forced-idle or battery simulation, and attempts restoration on failure or interruption. A disconnected ADB cable can prevent restoration; reconnect and run `adb -s DEVICE_SERIAL shell dumpsys deviceidle unforce`, `adb -s DEVICE_SERIAL shell dumpsys battery reset`, and restore Wi-Fi/mobile data to their recorded baseline values. Use the original ADB port where applicable.

The test uses real Android connectivity and idle state, the production member retry worker, encrypted checkpoints and durable controls, with a model-free adapter. It verifies:

- A completed observer is not invoked again, and its saved evidence feeds the remaining member.
- A queued member does not dispatch offline and dispatches exactly once after validated connectivity returns.
- Offline retries are paced and enter the long-wait state rather than failing at five minutes.
- Network restoration does not clear a user's pause or stop; only explicit resume permits the paused member to dispatch.
- Only fixture-owned records are cleaned up. No user contacts, conversations or original research tasks are executed or deleted.

The runner stores `host-timeline.json`, `device-report.json` and `instrumentation.log` in its printed local report directory. `--output` selects that directory. No phone logs or private conversation contents are exported. This controlled instrumentation matrix does not certify a real provider/MQTT outage, unattended OEM background survival, permanent server-state loss, or days-long endurance.

### S26U result on 2026-10-02

- Installed v1.4.10 (1095) over existing user data; application and instrumentation builds succeeded.
- Actual Wi-Fi/mobile-data outage lasted 608,801 ms. The device entered deep `IDLE` for approximately 182 seconds, and the app observed the idle state.
- The queued member recorded 16 paced waits, entered long-offline waiting, and dispatched exactly once after network recovery. Its completed observer was not invoked again, and saved dependency evidence was retained.
- The paused member remained blocked after networking returned and dispatched once only after explicit resume. The stopped member dispatched zero times.
- The fixture made zero model requests. The Desktop scheduler stayed at zero active and zero pending tasks with the same latest completed task.
- Recovery completed 54,374 ms after validated connectivity returned. The remaining exponential-backoff delay explains this tail; a bounded network/transport-ready wakeup is a follow-up latency improvement, not certified by this result.
- Four additional durable-checkpoint/control/repair device tests passed. The process-death test also passed on v1.4.10 (seed PID 23846, recovery PID 24002), with one final response, duplicate suppression, no unapplied fixture replies and no ordinary-chat leakage.
- All 108 targeted JVM tests passed again. Source-size, JavaScript syntax and whitespace checks passed.
- Wi-Fi and mobile data were restored to their initial enabled state. Forced idle and the simulated battery unplug were cleared. No original research task was rerun.
