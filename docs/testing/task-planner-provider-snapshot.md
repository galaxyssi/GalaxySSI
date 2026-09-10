# Task-scoped planner provider recovery

## Contract

The ordinary Android planner persists a non-secret snapshot of its planning
settings and the selected cloud contact, provider, endpoint, model and API style.
The encrypted session retains the binding after the pending planning operation
finishes, so another plan revision or a recreated runtime uses the original task
configuration. New tasks select the then-current configuration independently.

The snapshot never copies API keys, arbitrary contact properties or private
notes. Invocation resolves the current credential from the original contact.
Rotating that credential is supported. A different model selected for new work
does not change the old task's model. Deleted contacts, missing credentials or
changed contact/provider/endpoint/protocol identities fail explicitly rather
than silently sending retained task context to another destination. Recovery
specifications bind the snapshot with a configuration hash.

For contacts with a model catalog, resolution uses the original model's entry,
including its current endpoint and credential. A missing entry or credential
must not fall back to another model's credential. New conversation and task
cancellation paths clear the binding. Native-action arguments remain in their
existing durable input records, not duplicated in the session's model snapshot.

Existing current safety and disclosure checks continue to apply. Legacy records
without a snapshot keep their previous configuration-fingerprint validation;
this change cannot reconstruct settings that were never persisted.

## Verification scope

`AgentPlannerModelSnapshotDeviceTest` covers credential exclusion, credential
rotation, model changes, deleted contacts, route/protocol changes, full settings
round trips, encrypted planning input and session persistence after planning
completion, independent new task selection, and mismatched snapshot hashes.
It performs no network requests and does not install test contacts or credentials.

The live provider inventory on SM-T575 currently reports no ready cloud API
provider. Therefore cloud provider interruption/recovery acceptance remains open;
controlled tests are not a substitute for that acceptance. Existing pairing,
credentials and production data must be preserved while testing.

## Verified on 2026-09-10

- Android 1.1.49 (935) installed in place on SM-T575; first installation time
  remained 2026-09-07 07:17:23.
- Final debug/application/test APK build succeeded. JVM tests: 3,476 tests across
  502 suites, zero failures/errors, five skips.
- All 12 new model-binding instrumentation tests passed (1.877 seconds).
- Planning/replanning/model-loop/DAG recovery regression batch: 23 actual passes
  and six opt-in skips (105.319 seconds), including 32 durable replanning revisions.
- Physical reboot regression `20260910-initial-v1149` passed through normal app
  startup and the production recovery worker. PID changed from 17447 to 4598,
  and the boot ID changed. The original native `memory_status` task completed
  without resubmission or production data reset. This is an initial-planning
  startup regression, not a live-cloud-provider snapshot acceptance result.
- Repository and QNN package checks passed; all 73 AArch64 libraries passed the
  APK 16 KiB alignment audit.

Local logs: `build/provider-snapshot-verified-build.log`,
`build/provider-snapshot-device.log`, `build/provider-snapshot-recovery-device.log`
and `build/initial-planning-20260910-initial-v1149/`.
