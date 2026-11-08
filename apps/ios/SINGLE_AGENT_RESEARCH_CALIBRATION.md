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
