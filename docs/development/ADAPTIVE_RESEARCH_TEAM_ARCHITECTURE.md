# Adaptive Research Team Architecture

## Objective and completion criteria

GalaxySSI should operate as a durable professional team that improves verifiable shared results, rather than simulating multiple speakers. Success requires all of the capabilities below, production-path integration, resilience testing, and evidence from real model tasks. Scheduler unit tests do not demonstrate superiority over any single Agent or competing product.

| Requirement | Implementation / remaining acceptance |
| --- | --- |
| Goal and acceptance kernel | PR #3316 preserves original criteria and advances unfinished goals. A host-owned completion receipt now checks exact documentary deliveries and different-member reviews; model text alone cannot complete a newly executed goal. Remaining: semantic goal coverage and qualified computational/physical acceptance adapters. |
| Shared research workspace | Immutable typed revisions, author identities, parent designs and addressed counterexamples; optimistic revision checks reject overwrites. Managed cloud and explicitly bound native tool observations can be linked by exact host receipt and hash. Remaining: verified file/source attachments, other executor adapters and user-facing object inspection. |
| Asynchronous collaboration | This branch compiles explicit work dependencies into the existing event-driven DAG runtime. Ready reviewers do not wait for unrelated slow members. Remaining: coordinator-triggered graph expansion while unrelated work is still running. |
| Parallel candidate evolution | Separate versioned proposals and hypotheses can be compared, challenged and combined with exact parent references. Remaining: execution-backed candidate evaluation, branch lifecycle and automatic revised verification. |
| Independent verification | Different-member review constraints, revision digests and host-owned acceptance metadata prevent textual self-certification of new goals. Managed cloud and explicitly bound native observations are durable and exact references are resolved. Remaining: other native callers, remote adapters, source/file checks, computational/physical evaluators and semantic/domain validation. Documentary review integrity is not proof of scientific correctness. |
| Adaptive organization | PR #3316 adds justified, deduplicated recruitment behind existing authority and concurrency limits. Remaining: budget-aware single-Agent/team selection, duplicate-work detection, subgroup allocation and contraction. |
| Long-term team memory | Full research originals and typed object revisions survive; summaries are retrieval aids, not replacements. Remaining: longitudinal retrieval/conflict benchmarks and context assembly across large workspaces. |
| Durable execution | Existing checkpoints, claims, delivery receipts, pause/stop and offline recovery remain in use. Remaining: new workspace/graph chaos matrix and explicitly authorized Desktop/server ownership transfer during phone unavailability. |
| Team effectiveness evaluation | Deterministic correctness tests cover execution invariants. Remaining: fixed real-task corpus, equal-budget single-Agent/team baselines, blind outcome scoring, time/cost/rework/intervention metrics and policy feedback. |

No capability is complete merely because a data structure or green test exists. Each remaining item above must be implemented and verified before the full objective is marked complete. Paid provisioning, external contacts, uploads and physical experiments require their existing authorization. Simulation cannot stand in for empirical verification. Android force-stop and power-off do not guarantee computation; authorized remote continuity is separate work.

## Current work graph

Coordinator work entries may declare `depends_on` using stable work IDs and `dependency_policy` (`success` or `terminal`). The host maps these to round-specific dispatch IDs. Unknown dependencies, cycles, duplicate IDs and self-authored independent reviews are rejected as one plan, with repair feedback. Completed prior work is not replayed. Previous-batch dependencies are retrieved from saved originals.

Success-dependent work is skipped after its producer fails; explicit failure-diagnosis work may run after a terminal failure. Rejected recruitment removes transitive dependent assignments, not just the missing producer. Live concurrency remains bounded. A final assessment still waits for the planned graph; dynamic planning during an unfinished graph is not claimed here.

## Versioned research objects

The optional `workspace` array in a member artifact publishes hypotheses, evidence reports, counterexamples, proposals, experiments, artifacts, decisions and questions. The host supplies group/run/member/node attribution, version numbers, hash links and timestamps. New object IDs are derived from the group, author and stable local ID. Updates name an existing host ID and exact base revision. Conflicts reject the entire publication, preserving both the old revision and the original member response in the research archive.

Publication, revision rows and latest-head indexes are committed atomically in encrypted app storage. A stable dispatch publication key suppresses replay; a different result cannot reuse the same dispatch to create another version. The full original object body is preserved independently of prompt-size limits. Directory and body reads are paginated through `collaboration.recall` with `mode=workspace`.

Independent current-batch proposals are isolated. Assigned dependency recipients receive their producers' outputs; later rounds can read prior revisions. A hidden current revision does not hide its earlier visible predecessor. Group removal revokes access and removes the workspace, including late-publication protection. Every object remains `member_reported_not_verified` until a separately implemented host verification layer establishes what was actually checked. Authorship, version integrity and scientific correctness are distinct claims.

## Verification plan

1. Preserve the existing collaboration, recovery, control, provider and security regression suites.
2. Test producer/reviewer progress while an unrelated member remains blocked, failed producers with diagnostic continuations, invalid graphs and rejected recruits.
3. Test version conflicts, replay, cross-group isolation, independent proposals, historical retrieval, full originals, parent/counterexample references and storage failure.
4. Run isolated encrypted-store instrumentation on S26U, including separate seed/recover processes. Do not rerun the user's original research or invoke real-world tools.
5. Integrate authoritative evidence and independent acceptance next, then validate real Codex/DeepSeek tasks and the complete architecture against equal-budget single-Agent baselines.

## Evidence integration points inspected

`AgentNativeToolRegistry.finish` already produces host-owned invocation IDs, tool provenance, input/output hashes and optional verifier outcomes, and commits claimed side-effect outcomes before publishing success. `AgentNativeToolAuditDispatcher` writes audit records asynchronously; an immediate audit-index lookup is therefore not a reliable acceptance barrier. The evidence layer must preserve the actual result at its durable completion boundary, not parse a model's statement or race the audit writer.

Desktop `desktop_native_tools.py` also has native tool receipts and audit context; `codex_app_server.py` and `research_trace.py` preserve observed search events. A search/open event establishes that an operation occurred, not that the entire source was read or that its claim is true. These remote paths need a common scoped receipt reference tied to the paired executor, task, turn, member and artifact revision. Tests must reject fabricated, mismatched, failed, stale or cross-group receipts and distinguish execution integrity from scientific validation. Desktop integration remains pending; the Android native adapter is described below.

### Managed cloud observation adapter

`ActionExecutorAgentTeamMemberWorker` now binds each collaboration dispatch before execution. `MobileAgentActionExecutor` resolves that exact binding for the cloud path. `CloudImageAnnotationSession`, the tool boundary used by streaming cloud research, persists observations before exposing host receipts. Original output and hashes survive separately from compact model evidence; workspace publications resolve exact references and ignore forged host metadata. Non-collaboration conversations do not enable the recorder.

This is execution provenance, not semantic validation. A failed tool cannot become a successful test merely by being recorded, and a recorded `research_audit` remains a member assessment. The documentary acceptance checkpoint below now consumes exact references. The native adapter below adds another observed path; Desktop receipt adapters, real artifact checks and task-specific validators remain required for computational and physical acceptance.

### Native observation adapter

The native registry now records host-bound collaboration observations after committing a claimed effect. Managed local-model web execution carries the immutable dispatch source ID through its native loop, registry subset, effect scope and checkpoint binding. Raw native outcomes retain tool provenance, verifier status and replay markers. Failed verification cannot become returned evidence. Host metadata is separate from executor output; model arguments and generic attributes cannot supply the member binding. Non-collaboration invocations skip the recorder without opening its database.

Observation storage failures preserve the completed tool result with a non-durable warning, not a successful evidence receipt or a retry instruction. Same-member retries replay their existing effect; different members cannot borrow that effect by reusing its key. Checkpoint recovery retains the exact reference without executing or recording the operation again.

Coverage is deliberately explicit: the common registry boundary and managed local-model web path are wired. Native callers without a unique managed dispatch identity and remote Desktop/Codex executions are not silently attributed from a shared conversation or model name. Native contract verification is not domain-specific scientific/computational acceptance; qualified validators remain outstanding.

### Host-owned documentary acceptance

New goal executions no longer finish solely because a coordinator writes `achieved`, `met` and nonempty evidence strings. `CollaborationGoalAcceptance` resolves exact saved delivery/review versions, checks preserved criteria, current revision digests and independent author identity, rejects failed/assessment observations, and issues typed metadata outside model-controlled JSON. Previous contributors to the same delivery cannot serve as its independent reviewer. The receipt is bound to the original goal, criteria, root run, turn, coordinator node and unchanged complete assessment; it survives encrypted checkpoint recovery. Rendering reads the checkpoint metadata, not the evidence database.

This adapter checks documentary handoff and review integrity only. It cannot judge that every original requirement was captured faithfully, that all claims are true, or that a physical/computational experiment ran correctly. Unsupported verification types fail closed and receive actionable continuation feedback; available research/execution work can still continue. They cannot be relabeled documentary to bypass established criteria. Qualified validators and semantic coverage checks remain unfinished work.

Historical completions are not silently re-certified or restarted during upgrade: old records without an activated gate retain `unverified_history`. Creating a new goal, receiving a new execution event, or continuing an unfinished batch activates the host gate. Existing user pause/stop and recovery rules remain authoritative.

## Recorded verification: 2026-10-02

- Android source, built APK metadata and installed S26U package agree on **1.4.12 (1097)**. The existing installation was upgraded without clearing application data.
- **198 JVM tests across 19 suites passed**, with zero failures, errors or skips. This includes the existing collaboration regression selection and the new workspace, graph and recruitment cases.
- **Five isolated instrumentation cases passed on S26U**: encrypted workspace revision/replay/removal, dependency continuation while unrelated work is blocked, recruitment projection recovery, unfinished-run retention after 205 newer completions, and goal-criteria checkpoint reopening.
- A separate **seed/recover process pair passed**. The recovery ran in a different Android process and read the original preserved decision from encrypted storage. The fixture group was removed after recovery. This is process-boundary validation, not a new device-reboot test.
- The first instrumentation pass exposed a test method with a non-void inferred return type. The test entry point was corrected to `Unit`, rebuilt and rerun successfully; application code was unchanged by that correction.
- `git diff --check` and the Kotlin source-size policy passed. `npm run check` remains blocked by pre-existing i18n-policy findings in unchanged Android, Watch, AR glasses, Desktop and documentation files.
- No real model requests, original research reruns, contact messages or physical-control tools were executed. These tests do not establish research quality, scientific validity, real-provider resilience or a multi-agent advantage over an equal-budget single Agent.

### Managed cloud evidence follow-up: 1.4.13 (1098)

- Android source, built APK metadata and installed S26U package agree on **1.4.13 (1098)**. Installation preserved existing application data.
- **225 JVM tests across 22 suites passed**, with zero failures, errors or skips. Coverage includes immutable dispatch bindings, exact original outputs, forged receipts, cross-member isolation, checkpoint retention, cancellation and evidence-storage failure without repeating a completed operation.
- **Six isolated instrumentation cases passed on S26U**. The new case invokes the production local `research_audit` tool through the cloud tool session, reopens the encrypted observation, links it to a workspace revision and removes its fixture group. The five workspace, dependency and goal-continuity regressions also passed.
- An additional evidence **seed/recover process pair passed**, with different process IDs (16896 and 17098). Recovery read the persisted dispatch binding and original tool observation, then deleted the fixture group. This validates process persistence, not device reboot or real-provider recovery.
- `git diff --check` and the Kotlin source-size policy passed. The repository-wide `npm run check` still reports the pre-existing i18n-policy findings described above.
- No live model requests, original research reruns, contact messages or physical controls were used. A recorded local assessment is not an independent scientific verifier. Native/remote adapters and independently grounded goal acceptance remain pending.

### Documentary acceptance checkpoint: 1.4.14 (1099)

- Android source, debug APK metadata and the installed S26U package agree on **1.4.14 (1099)**. Existing application data was preserved.
- **240 JVM tests across 23 suites passed**. The 15 new acceptance cases cover immutable requirement matching, exact versions, prior-author self-review, modified records, missing evidence, unsupported empirical claims, scoped host metadata, snapshot reads and historical upgrade behavior.
- **Ten isolated S26U instrumentation cases passed**, including all six prior workspace/evidence/continuation cases and four new acceptance cases. The production managed member bridge issued the host acceptance receipt using a local fixture provider; a forged receipt in model text was rejected; encrypted reopening preserved a validated result; upgrade did not restart a historical completion.
- A separate **seed/recover pair passed** in Android processes 29991 and 30449. The second process recovered the host-bound acceptance result without re-executing the fixture, then removed its group and dedicated execution database.
- `git diff --check` and the Kotlin source-size policy passed. `npm run check` still fails the pre-existing i18n-policy findings in unchanged files; none reference this change's source files or architecture/protocol documents.
- Tests used dedicated local fixtures, including a stub provider through the production dispatch bridge. They did not submit live model requests, send contact messages or operate physical controls. These results do not establish scientific correctness, semantic completeness of every original goal, computational/physical acceptance or a measured multi-agent quality advantage.

### Native execution evidence: 1.4.15 (1100)

- Android source, APK metadata and the installed S26U package agree on **1.4.15 (1100)**. Installation preserved application data. No UI or Desktop code was changed.
- **338 JVM tests across 30 suites passed**, with zero failures, errors or skips. Eleven new cases cover native result integrity, exact member bindings, forged metadata, failed verification, ordinary-call bypass, observation write failure, effect separation, result projection and durable model-loop recovery.
- **Eleven isolated instrumentation cases passed on S26U**: the ten existing workspace, cloud observation, dependency, goal continuity and acceptance regressions, plus a production default-registry/subset case that creates and reads an app-private file, checks exact encrypted evidence and member isolation, and removes its fixture.
- A separate **seed/recover process pair passed** with process IDs 21600 and 21722. The second process read the original native result and host receipt from an encrypted checkpoint, resolved its durable dispatch binding and evidence, and cleaned the fixture group, file and checkpoint contents. No tool re-execution was needed for recovery.
- The first unit pass exposed shared-key cross-member replay; the final implementation isolates managed effect scopes and passes the regression. The first device fixture omitted a required file-creation idempotency key and was correctly rejected; the fixture was corrected and passed. No tool permission or idempotency guard was weakened.
- Debug application and instrumentation APK builds, `git diff --check`, and the Kotlin source-size policy passed. `npm run check` still fails pre-existing i18n findings in unchanged files; none name this change's files.
- No real model requests, original research reruns, contact messages or physical controls were executed. This verifies Android execution provenance and process recovery, not native model inference quality, remote Desktop receipts, qualified computational/physical acceptance, device-reboot/long-offline recovery or a measured multi-agent advantage.

See the [workspace protocol](../protocol/Collaboration-Research-Workspace-v1.md) for field meanings and trust boundaries. The full architecture remains in progress according to the completion table above.
