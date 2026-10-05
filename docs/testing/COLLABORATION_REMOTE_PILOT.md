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

### Conversation-scoped preparation

The normal model-picker UI also remembers target preferences for later use.
For an experiment that must leave those preferences unchanged, the opt-in
`CollaborationRemotePilotSelectionDeviceTest#prepareConversationSelectionWithoutChangingDefaults`
uses the same App selection store with `rememberAsDefault=false`. It creates a
dedicated conversation, reads back the saved model and effort, and asserts that
all `default.*` settings and the active conversation are unchanged. It makes no
model request and does not connect, stop, or resume other tasks.

Required arguments are `remotePilotPrepareSelection=true`,
`pilotDeviceModel=SM-S9480`, `remotePilotTarget`, `remotePilotModel`,
`remotePilotEffort`, and a fresh safe JSON basename in
`remotePilotSelectionOutput`. Target, model, and effort must be explicitly
supplied and advertised by the available target; there is no model default.
The output contains only the saved conversation ID and selection metadata.
Selection writes are flushed before instrumentation returns; the local marker
is a static assistant note, not a running-process event.
Use that conversation ID for the paired fixture and freeze the matching values
in its private protocol. This is a test setup helper, not a new product UI.

Instrumentation may restart the target App process. Check for existing work
before running either fixture; do not interrupt active user research without
authorization. Installing only a test APK is supported when the deployed
production sources and signature match; this does not constitute a new main
App build or release.

After archiving the completed report, the opt-in helper method
`removeSelectionAfterConfirmedPilotCleanup` removes only that dedicated
configuration conversation. Supply `remotePilotCleanupSelection=true`, the
device model, `remotePilotSelectionOutput`, and `remotePilotReport`. It requires
matching selection identity, a finished report, and confirmed STOP/empty pending
owners for every slot. Reports remain intact and global defaults are unchanged.

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

The test-only dispatch guard binds the transport's `agent_instance_id` to the
stable person, not the graph node. Single uses one remote conversation namespace;
team uses separate author and reviewer namespaces. Node, owner, idempotency, task,
and source-message identities remain distinct. Dispatch is sequential, and the
guard validates the original node before this transport-only adjustment. This
does not change production member routing. Verify actual provider thread reuse
from receipts; a requested namespace alone is not proof of context continuity.
Repeated task material and dependencies can remain in provider history, so this
is not an equal-token treatment.

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
multiple provider requests within one dispatch. Each protocol must fit explicit
per-round authorization or an applicable standing authorization with unchanged
limits. Authorization for a different live fixture is not implicitly reused.
Local unit tests and compilation do not authorize live execution.

## Evidence and cleanup

`remote-<pilot_id>-report.json` is reserved before the first call. It records all
assigned slots, including unattempted and failed ones, the App selection source,
protocol digest, dispatch identities, prepared-prompt digests, output, truncation,
execution time, and cleanup time. Requested model/effort are not asserted to be
the actually served values. Provider requests, tokens, and billed cost remain
null until independently joined to complete original provider receipts.

Use `codex_trial_capture.py` with scope `galaxyssi.codex-trial-scope.v2`
when stable people execute several nodes. It retains `expected_nodes` and adds
an ordered `assignments` list, each with `node_id`, `transport_instance_id`, and
`source_message_id` (a string). Join by the exact phone journal source identity,
not member name, task order, or model. Unknown messages and mismatched people
remain visible as issues. The v1 scope remains available for older node-scoped
captures. Neither scope starts, resumes, or cancels any task.

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

### Optional frozen candidate artifacts

Explicitly opt in with `remotePilotFreezeArtifacts=true` (omitted or `false`
preserves the existing cleanup behavior). Record this choice in the private
experiment plan before execution. This test-only path captures a successful,
untruncated runtime result before cleaning its conversation and execution store.
It does not make another model request, change the App selection, or modify
production evolution/skill acceptance policies.

The captured object contains exact draft, review, and final outputs plus the
phone-side dispatch journal. Its source binds the protocol digest, case, arm,
slot, run, conversation, turn, task, target, requested model/effort, and task-text
digest. Three distinct completed node dispatches must agree with that source.
The exact serialized payload and final output have SHA-256 digests; restored
content must match the caller's expected source and reference. These hashes
detect content changes; they are not signed attestations of model identity or
truth, and phone dispatch records do not prove provider request counts.

`CollaborationPilotArtifactStore` writes into the separate encrypted test
database `remote-pilot-artifacts-<pilot_id>`. A transaction permits an identical
retry but rejects a different payload for an existing source. Corrupt existing
records fail closed instead of being replaced. The per-slot report records the
candidate reference and source; a capture failure marks that slot failed and
preserves its ordinary output/failure report. Normal cleanup never deletes the
candidate store. Archive this private evidence before explicitly clearing its
dedicated test namespace; it may contain sensitive output and is not for Git.

Every object is labeled `unverified_candidate` and grants no permissions. It is
not installed as a procedure skill, automatically supplied to future tasks, or
treated as a successful innovation. Independent production review remains
mandatory for retained skills. In particular, an all-single-person arm cannot
silently invent an independent reviewer to satisfy that rule. A future fair
learning comparison needs a separately specified external evaluator for both
arms, fresh target contexts, a withheld-artifact control, and regression tests.
This increment supplies persistence/retrieval, not that complete experiment or
proof of cross-task learning.

## Local verification

Run `CollaborationRemotePilotTest`, `CollaborationPilotPlanTest`,
`CollaborationLiveModelSelectionTest`, and `CollaborationReasoningSelectionTest`,
plus `:app:compileDebugAndroidTestKotlin`. Tests cover configurable App selection,
unchanged assignment controls, synthetic execution of both real runtime graphs,
protocol validation, journaling failure, deadlines, and replay rejection.

`CollaborationPilotArtifactTest` runs local synthetic graphs for both arms and
checks exact output recovery, attribution, corruption, and invalid-result
rejection. `CollaborationPilotArtifactDeviceTest`, enabled only by
`candidateArtifactSynthetic=true` on SM-S9480, uses deterministic local workers
to check encrypted persistence after source cleanup, reopened-store retrieval,
atomic competing writes, and corrupt/foreign-source rejection. It makes no model
or transport call and never operates a user conversation. These synthetic
results must not be presented as real-model learning or efficacy measurements.

For Kotlin-only checks on machines without the native-memory Rust toolchain,
`-x :app:buildNativeMemory` excludes that independent build task. This is not a
successful APK build or device acceptance; do not install an APK built with a
missing required JNI library.
