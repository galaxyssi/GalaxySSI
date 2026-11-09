# Single-agent research calibration

The iOS XCTest fixture uses `galaxyssi.single-agent-research-calibration.v1`
to enroll one exact research assignment in the production milestone store.
The legacy `galaxyssi.single-agent-calibration.v1` format does not enroll.
There is no new UI setting or remote request that can enroll an assignment.

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
