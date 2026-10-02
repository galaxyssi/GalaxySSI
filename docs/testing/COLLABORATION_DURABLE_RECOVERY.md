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

## Goal-driven continuation and stopping-limit audit

The v1.4.11 change applies to Android collaboration research groups, including members executed by remote Desktop Agents. The Android host owns acceptance and continuation; it does not add a second search loop inside Codex.

| Prior restriction or terminal condition | New behavior |
| --- | --- |
| Five stages per researcher plus four coordinator stages | Removed. The coordinator proposes work based on current evidence gaps; there is no total step or round limit. |
| A final coordinator paragraph completes the whole goal | Removed for new goal-driven runs. A structured acceptance assessment must preserve every established criterion and report evidence for each fulfilled requirement. Unfinished work schedules another durable batch. |
| Research required 3-12 selected members | The workflow now works with two or more selected group members. Explicit research selections are not clipped to 12. Non-research team admission is unchanged. |
| At most 64 research DAG nodes | Removed as a research goal/admission bound. Live execution remains semaphore-limited by the device profile. A large plan queues rather than increasing simultaneous model calls. |
| Selected member count must fit currently free provider slots | Research groups wait for capacity through the existing paced worker; no longer reject the group solely because all members cannot start simultaneously. |
| Only the latest 200 runs survive | Only completed history is pruned. Pending, interrupted, continuing and externally blocked goals remain in the execution store. |
| Same-turn archive evidence was always inaccessible | Completed earlier goal batches can be recalled; current-batch independent outputs remain isolated. Full originals remain archived. |
| A failed/malformed coordinator response was terminal | It becomes a persisted replan checkpoint. Repeated empty/invalid/no-new-work plans back off from 30 seconds to 15 minutes, without an attempt-count ceiling. |
| A temporary provider/transport failure ends the objective | Existing member reconnection has no attempt ceiling. A returned subtask failure is evidence for the next goal assessment, not proof that the objective is complete. |

The host preserves the same run, task, conversation and user goal across batches. New work has fresh dispatch identities; exact completed work IDs are not executed again. Duplicate advancement uses an expected-primary compare-and-set. Late responses must match exact stage ownership and cannot attach by provider name to another batch. Each encrypted transition archives the previous checkpoint atomically with the next checkpoint. Updating the application does not automatically reopen old completed research runs; an explicit follow-up can start goal-driven continuation.

### Boundaries deliberately retained

- User pause, stop, permission checks, authorization boundaries, tool safety checks and cancellation are not removed.
- `blocked` is a non-success waiting state with a concrete missing resource/authority and resumption condition. Feasible computation, source verification and artifact work take precedence over blocking. The user can resume or supply new information without replaying completed work.
- An unavailable physical laboratory cannot be replaced by fabricated experimental evidence. Acceptance evidence is model-reported, not an automatic scientific proof of correctness.
- Live concurrency, model context/output windows, per-call I/O timeouts and retry pacing protect resources. They are not a goal-level step ceiling. External provider quotas, credit limits, credentials and Android force-stop/OEM scheduling remain real constraints.
- Android planner/model-loop count budgets are already disabled in their production policy (`enforceCountLimits=false`). Attempt-level no-progress detection remains. Desktop web-tool `max_rounds` bounds one tool invocation, not the collaboration goal; the coordinator can request further work from saved evidence.
- Unrelated scheduled research/self-evolution jobs have their own policies (including attempt limits), and non-research teams still have their existing admission policy. This change does not globally disable those policies or user-specified budgets.
- The group directory still supports up to 1,024 member profiles. This is distinct from the number of work steps or batches; this change does not claim 1,024 simultaneous live model calls.

### Regression coverage

`CollaborationResearchWorkflowTest` covers more than 1,000 batch continuations under the same goal, bounded live concurrency with more than 64 queued steps, acceptance criteria preservation, external blockers with remaining feasible work, malformed assessments, failed providers, exact-work deduplication, stale-response isolation and earlier-batch archive access. These are deterministic model-free tests, not a claim that 1,000 real model calls or real laboratory experiments succeeded.

`CollaborationGoalLoopDeviceTest` uses a dedicated encrypted fixture database for reopen/transition/archive verification and unfinished-run retention beyond 200 completed runs. It neither calls a model nor replays an existing user research task.

### Verification on 2026-10-02 (v1.4.11 / 1096)

- 163 JVM tests passed across 15 collaboration, control, adapter, dispatch, security and recovery suites; zero failures/errors.
- The goal-loop fixture completed 1,001 work batches and 1,002 coordinator assessments without changing the goal/root identities or replaying completed work. These were model-free calls.
- An 80-item work plan executed with at most three simultaneous workers. The separate admission test accepted 16 research members on a provider with zero currently free slots, while missing-permission admission remained rejected.
- Application and instrumentation APK compilation passed, as did source-size and whitespace checks.
- ADB detected no connected device. The new encrypted-store device tests are compiled but not run; no phone was installed and no original research task was restarted. Real Codex/DeepSeek acceptance, true process death between goal batches and physical experiment integration remain unverified for this change.

## Adaptive recruitment and resource recovery

The goal controller can propose a `recruit` entry with a stable vacancy ID, an existing authorized member template, a role, a distinct scope, and the reason additional help is needed. It must assign concrete work using `recruit:<vacancy-id>` in the same batch. The host allocates a persistent English name and person ID, inherits the template's provider/model/capabilities, and keeps the existing concurrency and permission checks. A researcher, architect, developer, tester or domain expert is a role, not a new grant of authority or proof of expertise.

Vacancy and scope deduplication prevent repeated assessments from recruiting the same position again. The encrypted run checkpoint acts as the durable outbox for group-directory projection. Projection is idempotent, occurs before dispatch, preserves existing member edits, and is acknowledged in the execution store. A crash between the two stores can repeat projection but cannot create a duplicate person. Removed/changed templates and a full 1,024-member directory reject recruitment and return feedback to the coordinator for reassignment; they do not mark the goal complete. User removal or provider changes are checked again before a recruited member executes.

For an unmet resource or permission condition, the host schedules a traceable resolution assignment before accepting an externally blocked state. This work researches authorized alternative tools, public data, compute and experimental platforms; compares prerequisites, availability, limitations and cost; and evaluates whether safe simulation or a smaller reproducible calculation can advance the goal. Successful discovery is recorded under a host-owned work ID and is not repeated merely because the coordinator restates the same stable blocker. Failed discovery retries with backoff; it has no attempt-count completion rule.

Waiting requires a concrete reason, an observable resume condition, completed resolution work and documented unavailable/inapplicable/approval-required alternatives. Available alternatives should produce further work instead of waiting. Explicit user resume or new input reopens planning. A simulation cannot fulfill an established `physical` verification criterion; changing that criterion to `computational` is rejected. All evidence remains model-reported and needs actual source/artifact review: a structured claim is not independent scientific certification.

Discovery does not authorize purchases, account registration, contacting providers, private-data uploads, physical experiments or bypassing denied permissions. Those actions still require the appropriate authorization and capabilities. The implementation does not automatically provision external laboratories or guarantee any laboratory's availability. User pause and stop remain authoritative.

### Recruitment/recovery verification on 2026-10-02

- 179 JVM tests passed across 17 suites with zero failures/errors, including 11 recruitment and five resource-recovery tests.
- The model-free recruitment fixture admitted and ran 20 new members behind the existing two-slot concurrency limit. Duplicate vacancies, repeated scopes, cross-task identity reuse, edited templates, rejected directory projection and reassignment feedback are covered.
- Resource/permission blockers schedule resolution work before waiting. Successful discovery is not repeated, failed discovery is paced, and simulated evidence cannot meet a preserved physical verification criterion.
- The 1,001-batch continuation, 80-item queued-work, pause/stop, late-response, dispatch, security and recovery regressions still pass.
- Application and instrumentation APKs built successfully at v1.4.11 / 1096. Kotlin source-size and whitespace checks passed.
- An additional encrypted-store instrumentation test compiles for interruption between group-directory projection and checkpoint acknowledgement. It also verifies replay deduplication and that an acknowledged, subsequently removed recruit is not silently recreated.
- ADB still detected no phone. The new device tests, real Codex/DeepSeek recruitment and real external-resource discovery remain unverified; no installation, physical experiment, account provisioning or original research rerun was performed.
