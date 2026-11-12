# Frozen collaboration pilot artifacts

`AgentFrozenPilotArtifactTests` ports Android #3393 to the iOS production
team runtime with synthetic workers. A candidate is frozen before the
isolated run is removed. It binds the frozen protocol, case, arm, slot,
run, conversation, turn, task and requested model controls to one distinct
dispatch per node. The saved results must match the UTF-8 outputs returned
by all three workers; runtime truncation or an unsuccessful node prevents
the freeze.

The test vault uses the app's authenticated encryption and an isolated key.
A source has a stable artifact ID. Its exact payload has a separate SHA-256.
An identical write is replay-safe. A competing write cannot replace the
original. The vault is separate from execution state and supports reopening
with the exact original locator after cleanup.

## Opt-in synthetic run

Run `testOptInFreezeSyntheticPilotArtifact` with:

- `GALAXYSSI_FREEZE_PILOT_ID`: a dedicated synthetic pilot ID.
- `GALAXYSSI_FREEZE_PROTOCOL_FILE` and `GALAXYSSI_FREEZE_PROTOCOL_SHA256`:
  an XCTest-readable frozen protocol file and its exact lowercase SHA-256.
- `GALAXYSSI_FREEZE_REFERENCE_FILE` (optional): the locator attachment from
  a previous run, to reopen it without starting a new execution.
- `GALAXYSSI_FREEZE_EXPORT_DIRECTORY` (optional): an existing directory
  where the test can explicitly export a plaintext synthetic probe envelope
  as `<sha256>.json`, compatible with iOS #4263. This hash is for the exported
  envelope and differs from the vault payload hash.

Keep the same test installation to reopen the encrypted vault. Only fixture
artifacts are kept in `Application Support/XCTest-FrozenPilotArtifacts`.
Do not use real task data or commit exported files. The artifact is
unverified and grants no permissions. This fixture does not call Desktop
or a model and does not prove learning, transfer, independent acceptance,
or equal provider cost.

## Recovering a completed Android pilot report

`AgentPilotReportRecoveryTests.testOptInRecoverCompletedAndroidPilotReport`
reconstructs candidates locally without dispatching model work. Supply the
original `galaxyssi.remote-collaboration-pilot.v1` plan and completed
`galaxyssi.remote-pilot-report.v1` report:

- `GALAXYSSI_PILOT_REPORT_RECOVERY=1`
- `GALAXYSSI_PILOT_REPORT_PROTOCOL` and `GALAXYSSI_PILOT_REPORT_PROTOCOL_SHA256`
- `GALAXYSSI_PILOT_REPORT_INPUT` and `GALAXYSSI_PILOT_REPORT_SHA256`
- `GALAXYSSI_PILOT_REPORT_MAX_DISPATCHES` (the original phone-side allowance)

Only a successful, untruncated report with exact assignments, matching
dispatch attribution and confirmed STOP with no pending remote owners is
eligible. The test attaches candidate locators and a recovery receipt. Use
the existing reference-file export workflow to bind a recovered candidate
into an iOS probe. Conflicting artifacts are never overwritten. Provenance
is `completed_test_report`, not a runtime capture or provider attestation.
Keep private inputs, receipts and exported candidate text outside Git.
