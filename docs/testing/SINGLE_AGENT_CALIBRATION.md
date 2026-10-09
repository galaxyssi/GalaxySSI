# Free-running single-agent calibration

The opt-in `CollaborationAdaptivePilotDeviceTest.runAdaptiveRemotePilot` entry
also accepts `galaxyssi.single-agent-calibration.v1`. It uses the same frozen
protocol fields, App-selected model and reasoning effort, exact device binding,
production worker, remote delivery and bounded cleanup as the adaptive-team
entry. Protocols, task data, original outputs and research results are not bundled
with the app or committed to the repository.

The single-agent format requires exactly one member and `maximum_dispatches: 1`.
That is one phone-to-Desktop dispatch, **not** one provider request or tool call.
The selected remote agent can use its normal tool loop within the registered
time/resource envelope. The fixture does not split the task into draft, review
and final nodes, create a coordinator, impose a research-stage JSON response or
replace the production prompt. Admission fails before I/O if the complete goal
is missing from that prompt; long input is not silently truncated.

## Outcome interpretation

Reports record `execution_mode: single_agent` and
`test_scope: execution_delivery_only`. A valid completed execution returns
`single_agent_returned_goal_unverified`. The integration check requires one
bound, hash-intact result, a successful execution checkpoint, confirmed cleanup
and preservation of the user's selected conversations. Timeout, cancellation,
missing replies and extra dispatches do not pass this check.

This delivery check is deliberately different from the adaptive team's
host-goal-acceptance check. Never compare their `test_verdict` fields as task
quality. External task evaluation is still required for both. The fixture leaves
`goal_verified_by_external_evaluator`, `scientific_capability_gain_proven`,
`equal_budget_comparison` and `single_agent_tool_delegation_audited` false.

Production tool availability is retained, not an isolated capability sandbox.
Audit provider tool traces for delegation before describing the run as a verified
single-agent baseline. Provider request count, input/output tokens, context and
billed cost need separate accounting. One phone dispatch is not equal compute
to one team dispatch. Compare results over matched observable resources and
report residual accounting uncertainty rather than claiming equal cost.

## Non-effects

These formats belong to test fixtures. They do not change the user-facing
collaboration planner, its member limit, recruitment, goal acceptance, model
selection or normal research duration. A single-agent calibration result cannot
relax the production requirement for independent evidence where applicable.
