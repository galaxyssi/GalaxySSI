# Native connector acceptance evidence

Follow-up to Android #3119, based on main
`8a794e82ebe8f09790e41139295ffb7ac1ee9701`.

## Actual integration gap

The iOS queued executor prepares a receipt before the backend operation starts.
It previously wrote `remote_task_status = queued` without any remote evidence.
The timing policy sees a nonempty remote status without an acceptance timestamp
and cannot classify that receipt as not accepted. Separately, the existing
authenticated native status projection never supplied the missing acceptance
anchor, preventing the not-running/live-stale timing stages from acquiring it.

Android distinguishes transport acceptance from local preparation in
`MobileNativeAgent.recordConnectorTransportAccepted` and requires owned remote
observation before timeout handling in `MainActivityConnectorTimeoutRecovery`.
This follows those evidence boundaries; it does not copy a new wire schema.

## Change

- New prepared receipts still say Queued, awaiting response, unverified, with
  the same request identity, generation and resource start time. They no longer
  manufacture a remote status. The existing transport recorder can set accepted
  only when invoked with the matching receipt source/contact contract.
- The existing authenticated native status projection sets a missing
  `transport_accepted_at` to the first durably accepted remote observation time.
  This happens only after its existing exact owner/scope/generation, monotonic
  sequence and clock checks. The coordinator already persists that projected
  receipt through owned task-state commit on both MQTT paths.
- Later status progress updates the status clock, not the original acceptance
  anchor. An existing anchor, including legacy metadata, is not rewritten.
  Status-only terminal observations still cannot complete, fail over or execute
  a task; uncertainty flags and ownership remain intact.

No migration rewrites old queue receipts. Local/cloud jobs do not gain a remote
status endpoint. No polling scheduler, automatic timeout failure or replay is
introduced. Generic active timeout/deferred discovery remains incomplete.

## Verification limits

Four XCTest methods are authored in already registered files, NOT executed.
They cover preparation before/at the not-accepted deadline, matching versus
foreign acceptance receipts, queued/running status anchors, later progress,
existing anchor retention and Codable round trips. Existing negative scope,
sequence, generation and terminal-status fixtures remain unchanged.

The source guard checks exact production deltas, the actual existing producer
and projection, and retains coordinator/transport/timing/recovery kernels.
No Swift compilation/typecheck, XCTest, device/network/restart acceptance,
CI watching or IPA is performed. This is not completion of Android #3119.
