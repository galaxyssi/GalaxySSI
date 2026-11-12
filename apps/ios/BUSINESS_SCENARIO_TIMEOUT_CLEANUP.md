# Recorded business test timeout cleanup on iOS

An observation timeout is evidence about the observer, not permission to
cancel or resend the task. The ordinary regression uses a synthetic fixture,
two real iOS task-supervisor jobs, and a dedicated temporary store. It verifies
that cancellation stops only the recorded task and preserves the report bytes.

For explicit cleanup of a previously recorded, synthetic local fixture, run
only `AgentBusinessTimeoutCleanupTests.testOptInCancelRecordedBusinessTimeout`
with these XCTest host environment variables:

| Variable | Value |
| --- | --- |
| `GALAXYSSI_BUSINESS_CANCEL_RECORDED` | `1` |
| `GALAXYSSI_BUSINESS_RUN` | Recorded run name, 1-64 ASCII letters, digits, underscores or hyphens |
| `GALAXYSSI_BUSINESS_CASE` | Recorded case, e.g. `A005` |
| `GALAXYSSI_BUSINESS_TURN_INDEX` | Zero-based index of the recorded timeout |
| `GALAXYSSI_BUSINESS_REPORT_SHA256` | SHA-256 of the exact original case report bytes |

Run the opt-in case only when the original fixture supervisor is no longer
running. It cannot observe an execution owned by another process. The test
reads only its fixture workspace at
`Application Support/XCTest-BusinessScenarios/<run>/synthetic-workspaces.json`.
The same directory must have a `catalog.json` with `catalogSHA256` and the
case report (e.g. `A005.json`) with `catalogSHA256`, `caseID`, `windowKey`
(`business-<run>-<case>`), the XCTest host's recorded vendor device ID
(`device`), and `turns`. Each turn has `state`, `workspace` (the encoded
`AgentWorkspaceKey`), exact `goal`, and `createdAtMillis` from the workspace.
These fields must come from the original fixture; do not create a timeout
report after the fact to bypass validation.

The original report is read-only. A separate receipt identifies the report and
turn, records the cancellation result and verifies both a terminal workspace
and an inactive local task. A changed workspace is not cancelled. This does
not send a remote cancellation, touch production app storage, run the live
Android Word campaign, or establish artifact or document quality.
