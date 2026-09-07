# Evolution recovery admission

For the subsequent cross-process extension in 1.0.41, see
[Evolution task OS ownership](evolution-task-os-ownership.md).

Desktop 1.0.40 extends restart recovery for isolated evolution tasks. This builds
on durable campaigns and verified integrated dependency outcomes, without
changing Android execution or restarting a running Desktop deployment.

## Recovery and ownership

- Recovery streams all task records, independently of the 500-item UI list limit.
  Invalid JSON and records whose filename does not match their task ID are skipped.
- A manager does not roll back its live background worker, synchronous worker,
  publication, or another operation that already reserved the task for recovery.
  Created-but-not-started threads reserve execution capacity too.
- Rollback cannot remove a worktree owned by a live execution or publication.
  Publication and execution cannot claim the same task concurrently.
- Cleanup runs outside the manager lock. The task is reloaded before a status
  transition, preserving cancellation even when cleanup fails concurrently.
- One unreadable task or cleanup error does not prevent unrelated task recovery.
  Audit events identify the task and error type without recording private content.

## Durable admission

Interrupted attempts keep the existing verified rollback behavior and attempt
policy. Eligible tasks are persisted as `proposed` with `desktop_restart`; this
durable state is the recovery queue, not an in-memory list of pending jobs.

`recover_interrupted(resume=True)` requests admission after scanning. It does not
override disabled self-evolution or `auto_start_tasks=false`. Enabled scheduler
ticks continue draining the queue using current serial/parallel capacity. Each
tick also caps starts to that capacity even when workers finish immediately.
Already reserved and running workers consume capacity. Unrelated new proposals
are not implicitly started by the recovery queue.

CI-repair tasks are resumed by CI head reconciliation. Campaign tasks are resumed
by their DAG, so generic restart recovery cannot bypass dependencies or a paused
campaign. Interrupted publications retain their explicit reconciliation state;
recovery never blindly repeats a GitHub publication.

## Validation and limits

Regression coverage includes 651 persisted interrupted records with only two
admissions, records older than the UI window, manager recreation, real worker
waves, cancellation races, corrupt records, disabled scheduling, CI/DAG ownership,
failed thread startup, and a subprocess that exits abnormally after writing a
pre-execution task. OS-owner tests crash the actual Python lock holder rather than
only terminating the Windows virtual-environment launcher.

These local operation guards do not constitute cross-process fencing of external
CLI side effects. The subprocess test does not kill a running coding CLI or prove
exactly-once external actions. Full device-reboot, orphan-CLI reconciliation,
multi-day checkpoint continuation, and S20U acceptance remain separate required
tests. This change is not a claim that the complete long-running Agent goal has
been delivered.
