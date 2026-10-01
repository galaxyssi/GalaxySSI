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

Production network outages, phone reboot/Doze, real Desktop stop acknowledgement, permanent server-state loss and multi-day waiting require a broader endurance matrix. Passing a checkpoint fixture does not certify all of these conditions.
