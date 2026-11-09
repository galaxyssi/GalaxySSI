# Single-agent research calibration

The iOS XCTest fixture uses `galaxyssi.single-agent-research-calibration.v1`
to enroll one exact research assignment in the production milestone store.
The legacy `galaxyssi.single-agent-calibration.v1` format does not enroll.
There is no new UI setting or remote request that can enroll an assignment.

## Free-running delivery baseline

`AgentSingleDeliveryCalibrationTests` covers Android #3470 separately. The
test-only `galaxyssi.single-agent-calibration.v1` format uses one responding
member and one dispatch, with no coordinator, research stage, dependency or
milestone enrollment. It preserves the raw goal and checks the normalized
member assignment against the production runtime and prompt builder before
the synthetic worker can return. The encrypted execution store is reopened
to check the exact result, then the isolated run is removed.

Run the unit tests without environment variables. To opt into the physical
device test, supply a synthetic JSON file readable by the XCTest host:

```json
{
  "format": "galaxyssi.single-agent-calibration.v1",
  "deviceModel": "iPhone16,2",
  "targetID": "fixture:codex",
  "modelID": "fixture-model",
  "reasoningEffort": "high",
  "memberID": "researcher",
  "objective": "Inspect the synthetic fixture.\nPreserve its original conditions.",
  "timeoutMillis": 15000,
  "maximumDispatches": 1
}
```

Set `GALAXYSSI_SINGLE_DELIVERY_PLAN` to the file path and
`GALAXYSSI_SINGLE_DELIVERY_PLAN_SHA256` to its lowercase SHA-256. Set
`GALAXYSSI_SINGLE_DELIVERY_DEVICE_MODEL`, `GALAXYSSI_SINGLE_DELIVERY_TARGET`,
`GALAXYSSI_SINGLE_DELIVERY_MODEL` and `GALAXYSSI_SINGLE_DELIVERY_EFFORT` to the
exact independently selected fixture values. Verify the intended Xcode
device separately when several devices have the same hardware identifier.
The attachment contains the synthetic result and its hash, not the goal.

This test does not contact Desktop or a model provider. The verdict is
delivery-only and cannot attest task acceptance, scientific correctness,
delegation, equal compute, or capability gain. The fixture never reads or
modifies the user's conversations or model settings.

The fixture uses the production team runtime with one responding member, no
dependencies, a frozen test model selection, and the original objective. It
counts worker invocations, not provider-internal model requests. Its worker
is synthetic and does not use the network.

The test publishes an unverified method through the normal milestone API,
finalizes its original references, reopens the encrypted history, and recalls
the same revision from a later assignment in the same group. A delivery-only
report cannot claim goal acceptance, scientific correctness, capability gain,
or learned transfer. An empty milestone archive is not method formation.

Run `AgentSingleResearchCalibrationTests` with the iOS XCTest target. Live
worker enrollment, model behavior, and iPhone/Desktop delivery need separate
validation.

## Cross-phase continuity

`testPilotContinuityRetainsExactMethodAcrossFreshAssignments` uses a
test-owned conversation and a fresh run and turn per phase. It publishes a
synthetic method in phase one, retains the negative execution verdict, and
checks the same exact workspace original and contraindication in phase two.
Both phases use the normal encrypted research history and scoped recall.
Each phase reserves its identity before touching the workspace. The predecessor
report and original are hashed; invalid, duplicate or interrupted reservations
are not silently retried.

For a two-process device check, run only
`testOptInPilotContinuityAcrossTestProcesses` with the following environment
variables configured on the XCTest host. Keep the same installation and select
the same device for both runs:

1. Set `GALAXYSSI_CONTINUITY_PHASE=1` and `GALAXYSSI_CONTINUITY_TOKEN` to
   a fresh UUID. Record the printed `GALAXYSSI_CONTINUITY_REPORT_SHA256`.
2. Start a new test process. Use the same token, set
   `GALAXYSSI_CONTINUITY_PHASE=2` and pass that digest as
   `GALAXYSSI_CONTINUITY_PREVIOUS_REPORT_SHA256`.

Phase two removes only its dedicated workspace and test Keychain entries.
Reservation and observer files remain in the test-owned
`Application Support/XCTest-PilotContinuity` directory. An interrupted
reservation requires inspection; a new study uses a fresh UUID.
The fixture neither uses an existing conversation nor invokes a model. An
observer's read establishes availability, not autonomous retrieval, model
use, a fresh provider thread, or improved task quality.

### Adaptive team phases

`AgentAdaptivePilotContinuityTests.testOptInAdaptivePilotPhase` runs a frozen
phase through the iOS team execution runtime and encrypted research history.
Use only synthetic inputs. The test never calls a model, contacts Desktop, or
reads the user's workspace. A missing fixture reply is a real failed worker
in the test runtime, not a reason to discard the phase's report.

Provide an XCTest-host-readable JSON file and its SHA-256 as
`GALAXYSSI_ADAPTIVE_PILOT_PLAN` and `GALAXYSSI_ADAPTIVE_PILOT_PLAN_SHA256`.
Set `GALAXYSSI_ADAPTIVE_PILOT_TOKEN` to a fresh UUID for a new study. Example
phase one:

```json
{
  "format": "galaxyssi.ios.adaptive-pilot-phase.v1",
  "index": 1,
  "objective": "Inspect fixture one.",
  "roster": [
    {"member": "lead", "target": "fixture:lead", "model": "fixture-model", "effort": "high"},
    {"member": "review", "target": "fixture:review", "model": "fixture-model", "effort": "low"}
  ],
  "replies": {"review": "Synthetic observation."},
  "retainWorkspace": true,
  "previousReportSHA256": ""
}
```

For the next phase, start a new XCTest process on the same installation and
device with the same token and ordered roster. Use the next sequential index,
a newly frozen goal and replies, and the previous printed
`GALAXYSSI_ADAPTIVE_PILOT_REPORT_SHA256`. Set `retainWorkspace` to false in the
last phase. The study keeps one group and fresh run, turn, and source IDs for
each phase. An interrupted reservation is not reusable.

Observer archives and execution reports remain under
`Application Support/XCTest-AdaptivePilot/<token>`; they are fixture
artifacts, not agent context. Each archive stores the exact canonical research
revision bytes with verified production hashes. The last phase removes only
its test SQLite workspace and Keychain entries before writing its report.
The tests do not prove autonomous retrieval, learning, fresh provider
threads, or improved task quality.

## Persisted conversation selection

The fixture reads the iOS conversation database's explicit active-selection
record before preparation, after the calibration and after removing only the
fixture conversation. It checks both an existing selection and an unset one.
The newest conversation is not a selection. These tests use isolated storage,
not the user's application database.

To run the optional physical-device case, select the verified device in Xcode
and pass `GALAXYSSI_CALIBRATION_DEVICE_TEST=1` and
`GALAXYSSI_CALIBRATION_DEVICE_MODEL=<exact hardware identifier>` in the test
configuration (for example, `iPhone16,2`). The test rejects simulators, missing
identifiers, wildcards, lists and mismatched models before creating a fixture.
Verify the device destination separately when two devices share a model.
The XCTest attachment records the model and the check performed. The test
verdict is the XCTest result, not evidence of live provider or multi-window
device behavior.
