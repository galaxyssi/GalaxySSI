# Remote collaboration engineering pilot

## Scope

`CollaborationRemotePilotDeviceTest#runPairedRemotePilot` is an opt-in Android
instrumentation fixture. It dispatches through the existing production path:
Android -> paired Desktop -> Codex adapter -> provider. It does not introduce an
API key, a new provider, a production model default, or an experiment settings UI.

The operator selects a target, explicit model, and explicit reasoning effort in
an existing App conversation using the normal model picker. The fixture reads
that conversation's saved selection and requires it to match the frozen private
protocol. Neither the model nor the effort is hardcoded. A later experiment may
choose a different advertised model without changing this fixture. Auto routing,
missing selections, retired/unavailable models, and mismatches are not silently
substituted. The original conversation and global defaults are not changed.

This is an open-tool engineering comparison, not the closed-book, equal-cost
pilot in `COLLABORATION_PAIRED_PILOT.md`. Existing cloud-only exclusions remain.
Production Codex tools and provider-side context are not certified isolated.
Prompt instructions to use supplied material are not a sandbox.

## Protocol and admission

Keep protocols, tasks, reference answers, reports, and provider receipts outside
Git. The private input JSON has exactly these top-level keys:

- `format`: `galaxyssi.remote-collaboration-pilot.v1`
- `pilot_id`: a new filesystem-safe ID; never reuse a completed/interrupted ID
- `target_id`: the selected paired Desktop Codex target ID
- `model_id`, `reasoning_effort`: the explicit App selection for this experiment
- `tool_scope`: `production_tools_not_isolated`
- `trial_timeout_ms`: an operator-approved per-slot wall time, 60000..900000
- `slots`: objects containing only `id`, `case_id`, `arm`, and `prompt`

Each case has one `single` and one `team` slot with identical task material.
The ordered slots are frozen before execution; choose and counterbalance order
in the protocol, not after observing outcomes. At most 32 slots and 12000 UTF-8
bytes per task are accepted by this small pilot. These test-only envelopes and
three-node graphs do not limit production autonomous research.

Both arms execute draft -> review -> revision with the same assignments and
task roles. Single uses Analyst for all nodes; team uses Analyst -> Reviewer ->
Analyst. Nodes use the same target, model, effort, and full supplied dependencies.
They are sequential. This fixture therefore cannot estimate parallel speedup.
It tests a narrow identity/coordination treatment, not all collaboration features.

Every node is validated against its assigned run, turn, conversation, task,
member, model, effort, and idempotency identity. Its dispatch is durably reserved
before the underlying executor is invoked. Deadline expiry, changed controls,
duplicate dispatch, truncated dependency context, and failed journal writes fail
closed. A reserved slot is never automatically rerun under the same protocol ID.

## Required instrumentation arguments

- `collaborationRemotePilot=true`
- `pilotDeviceModel=SM-S9480` (this fixture is restricted to the authorized S26U)
- `remotePilotTools=production_tools_not_isolated`
- `remotePilotInput=<safe-basename>.json` in the target App's external files folder
- `remotePilotSha256=<exact input file SHA-256>`
- `remotePilotSelectionConversationId=<conversation with the chosen App settings>`
- `remotePilotMaxDispatches=<separately authorized phone-side dispatch allowance>`

Each slot needs three phone-side delegate dispatches. This allowance is **not**
an API-request, token, tool-call, or monetary cap: the remote executor can issue
multiple provider requests within one dispatch. Obtain fresh authorization for
each protocol. Prior authorization for a different live fixture is not reused.
Local unit tests and compilation do not authorize live execution.

## Evidence and cleanup

`remote-<pilot_id>-report.json` is reserved before the first call. It records all
assigned slots, including unattempted and failed ones, the App selection source,
protocol digest, dispatch identities, prepared-prompt digests, output, truncation,
execution time, and cleanup time. Requested model/effort are not asserted to be
the actually served values. Provider requests, tokens, and billed cost remain
null until independently joined to complete original provider receipts.

The fixture excludes unrelated App handoff memory from its prepared prompt, but
does not claim isolation of all Desktop/provider context. It does not place
reference answers or scoring rubrics in execution prompts.

After each slot, durable STOP and remote-stop recovery must confirm no active
local handle or pending remote owner. Otherwise evidence and task state remain
for inspection and subsequent slots are not started. Confirmed cleanup removes
only the dedicated fixture conversation and execution data, after archiving its
report; it never switches the user's active conversation. A crash leaves the
reserved report as a rerun barrier, not permission to start another trial.

This report alone is not evidence of scientific novelty, quality improvement,
equal-budget superiority, a complete six-arm experiment, or longitudinal
retention. Those require separate protocols, scoring, isolation, accounting,
repetitions, and analysis of all assigned outcomes.

## Local verification

Run `CollaborationRemotePilotTest`, `CollaborationPilotPlanTest`,
`CollaborationLiveModelSelectionTest`, and `CollaborationReasoningSelectionTest`,
plus `:app:compileDebugAndroidTestKotlin`. Tests cover configurable App selection,
unchanged assignment controls, synthetic execution of both real runtime graphs,
protocol validation, journaling failure, deadlines, and replay rejection.

For Kotlin-only checks on machines without the native-memory Rust toolchain,
`-x :app:buildNativeMemory` excludes that independent build task. This is not a
successful APK build or device acceptance; do not install an APK built with a
missing required JNI library.
