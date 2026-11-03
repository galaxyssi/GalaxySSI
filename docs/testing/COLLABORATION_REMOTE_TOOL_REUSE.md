# Remote Reuse of Released Tools

`collaboration_run_tool` lets a remote Codex member execute a previously
released tool with new parameters in its originating App's native runtime.
It complements `collaboration_test_tool`, which runs a saved test plan.
Discovery alone is neither an execution nor evidence of learning.

## Contract

Start takes `mode=start`, a stable `execution_id`, integer `timeout_ms`, a JSON
`parameters` object, and exactly one exact `tool_release` or
`capability_channel` reference (`object_id`, integer `revision`, `sha256`).
Status and cancel accept only `mode` and the original `execution_id`.
There are no inline-code, source, oracle, networking, peer or scope overrides.

The implementation reuses the existing saved-tool request/result transport,
broker, authenticated task identity, App-owned journal and native executor.
There is no new queue, scheduler or polling service. The legacy wire operation
is still named `collaboration_tool_test_request`; its arguments select test or
run. Results explicitly identify `execution_mode`. An older receiver rejects
the new shape rather than treating it as a test or silently running elsewhere.

Before execution, the existing compiler checks source/test/release lineage,
the current capability selection, input schema, runtime identity and access.
The runtime must already be installed. Network stays disabled, no Desktop
fallback is added, and the native Linux runtime is not a security sandbox.
Read-only, plan-only and screen-analysis tasks cannot start this operation.

## Identity and Evidence

Execution IDs are scoped by group, run, turn, round, node and member. Repeating
the same start recovers its record; changing the selector, exact revision,
parameters, timeout or operation under that ID is rejected. Transport retries
retain both the original request and execution identity.

After an App process restart, completed results remain recoverable. Uncertain
unfinished work becomes interrupted and is not automatically reexecuted.
Cancellation does not erase completed evidence. Full native output remains in
the original evidence ledger, not in the small status response.

For `execution_mode=run`, a successful native receipt is not a judgment of
scientific validity, task quality or general applicability. Members must read
the complete original output and validate it against the new task's criteria.

## Verification Scope

- `test_collaboration_tool_run_bridge.py`: tool advertisement, exact arguments,
  finite JSON values, authenticated retry, task/turn binding, execution policy,
  callback routing and separation from web-search progress.
- `CollaborationSavedToolRunTest`: release/channel native mapping, persistence,
  duplicate identity, parameter changes, cancellation, process loss, scope and
  authenticated request validation.
- `CollaborationSavedToolTestDeviceTest`: encrypted test/run journal reopen and
  uncertain-effect handling, without running models or user tasks.
- `CollaborationSavedToolNativeDeviceTest`: actual broken/fixed Python tests,
  independent fixture release, fresh-task discovery, new-input execution using
  the remote adapter, and recovering the exact receipt without a second launch.

These are product tests with developer-authored fixtures. They do not prove a
live Codex/MQTT round trip, autonomous tool formation, cross-domain learning,
retention, matched-budget collaboration gains or a scientific discovery.
