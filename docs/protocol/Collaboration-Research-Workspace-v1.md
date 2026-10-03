# Collaboration Research Workspace v1

This contract extends Android's goal-driven collaboration execution. The app owns identities, dependencies and revision receipts. Member output is untrusted research material, not authorization or proof of correctness. It does not change the MQTT wire format.

## Work dependencies

Entries in the coordinator's existing `work` array may add:

| Field | Meaning |
| --- | --- |
| `id` | Stable business work ID; completed work is not dispatched again. |
| `depends_on` | Array of work IDs in the current plan or host-recorded successful prior work. |
| `dependency_policy` | `success` by default; `terminal` explicitly permits failure-diagnosis continuations. |
| `independent_review` | Requires a known, different author for every dependency. |

The host derives round-specific dispatch IDs from the stable work IDs. Duplicate IDs, self-dependencies, unknown dependencies, cycles and self-authored independent reviews reject the whole work graph. Rejection returns feedback to the coordinator; it does not partially dispatch the plan or publish its proposed recruits. Historical author attribution comes from persisted successful dispatches, not a newly supplied model claim.

Ready nodes execute under the existing concurrency and authority controls. Failure skips success-dependent nodes while terminal-policy diagnostics can continue. Independent branches need not wait for unrelated slow work. Opted-in research teams accept append-only `galaxyssi.work-expansion.v1` checkpoints while the graph is running. The final coordinator assessment waits for both original work and every accepted addition.

## Research object publication

An optional `workspace` array extends `galaxyssi.research-artifact.v1`. Each entry contains:

| Field | Meaning |
| --- | --- |
| `id` | Stable local ID for a new object, up to 160 characters. |
| `object_id` | Existing host-assigned ID for an update; empty for a new object. |
| `base_revision` | Exact expected head revision; zero when creating. |
| `kind` | `hypothesis`, `evidence`, `counterexample`, `proposal`, `experiment`, `artifact`, `decision`, `question`, `acceptance_review`, `candidate` or `candidate_event`. |
| `title` | Nonempty title, up to 240 characters. |
| `body` | Nonempty JSON object preserving the substantive original content. |
| `parents` | Exact `{object_id, revision, sha256}` references used to derive this version. |
| `resolves` | Exact references to preserved counterexamples or questions being addressed. |
| `observations` | Exact `{evidence_id, sha256}` references copied from host tool receipts. |

New object IDs are derived from the group, author and local ID. Group, run, turn, member, dispatch, round, timestamp, revision, previous hash and current hash are host-owned fields. Object kinds are immutable. Current independent work cannot be overwritten or read by an unrelated member. Reference targets must exist and be visible to the assignment.

All updates in one publication are validated before any revision is committed. A stale base revision rejects the complete publication. Revisions, head indexes and publication receipts commit atomically in encrypted storage. A dispatch can replay its identical publication, but cannot publish a different result under the same identity. Corrections require new work and an explicit new revision. Storage errors propagate instead of reporting a successful publication.

The host removes any member-supplied `workspace_receipt` before attaching the actual receipt. A recorded receipt establishes authorship and version integrity only. Objects are labeled `member_reported_not_verified`; neither an `outcome` field nor an independent member's agreement establishes scientific truth.

### Candidate history and automatic documentary checks

`candidate` bodies preserve substantive `content` and a `candidate` object with `operation`, `rationale` and exact inherited `criteria`. Operations are `propose`, `revise`, `combine` and `retire`. Revision/retirement names its exact active head as the sole parent; combination creates a new object from at least two distinct active parents. Retirement preserves the original content and criteria. There is no arbitrary eight-parent limit. Non-proposal changes require host-observed evidence.

`candidate_event` bodies contain a `candidate_event` object with `operation`, exact `targets`, a shared `criterion`, `check`, `rationale` and `outcome`. Compare uses at least two distinct candidates and reports `differentiated` or `inconclusive`; challenge/review uses one exact active version and reports `supported`, `refuted` or `not_tested`. Challenges include a correction. Independent review cannot be authored by any candidate contributor or ancestor author; supported review has no unresolved blockers and cites returned host tool originals. Events are immutable. Updating or retiring the candidate invalidates the applicability of its old review without deleting that review.

Both work expansions and goal assessments accept optional `candidate_cycles` entries:

```json
{
  "target": {"object_id": "host-id", "revision": 1, "sha256": "host-digest"},
  "criterion_id": "established-criterion",
  "editor": "authorized-person",
  "reviewer": "independent-person",
  "producer_work_ids": ["exact-current-producer"]
}
```

The criterion must already preserve documentary verification and required original observation types. Current-round live targets require explicit producer work with successful host result and read authority. The host owns `candidate-cycle:` work IDs and the task binding; models cannot supply or rewrite either. Its checkpoint records exact targets, phases, original criteria, assigned identities and pending requests. It shares the existing encrypted graph transaction, not a new model-controlled task store.

A refuted exact review can append `revise`, then `review` of the new version, under existing runtime capacity and pause/stop controls. These transitions do not need another coordinator model call. A different candidate can proceed concurrently. Publication must contain the single assigned exact revision/review; after a committed publication and process loss, the worker replays the host receipt instead of reexecuting. Unknown/in-flight dispatches wait for authoritative reconciliation. Terminal errors retain feedback for coordinator replanning; they are never converted to successful verification.

A host-completed documentary review with no committed publication may be settled as
`retryable_review`. The coordinator can explicitly enroll the same exact candidate
version with `retry_review: {node_id: "old completed dispatch", reason: "specific
publication correction"}` and an authorized independent reviewer. This appends new
work; it does not replace the original dispatch, change the source/criterion
contract or rerun an experiment. The old outcome is retained in
`prior_settlements`. Consumed retry requests are idempotent, while a newer pending
attempt cannot be overwritten by replaying an older request for the same version.

This exception requires an actual host success result, not a progress message or
an inference from elapsed time. Failed, cancelled, skipped, unknown and in-flight
executions are ineligible, as are repairs and already published reviews. Admission
still respects pause/stop, capacity and scoped producer dependencies. A late old
publication prevents new admission, execution and publication through the existing
workspace transaction checks. No fixed retry count is added; an explicit useful
correction is required, not extra votes until a preferred answer wins. This is not
automatic offline owner replacement. See the [reassignment tests](../testing/COLLABORATION_REVIEW_REASSIGNMENT.md).

These checks enforce documentary lineage, scope and execution integrity. They do not rank scientific merit, certify a physical experiment, or make a majority vote true. Pending cycles prevent goal acceptance; settled cycles do not by themselves allow acceptance. Computational/physical candidate evaluators and real-provider repair reliability need separate acceptance.

## Host-observed tool evidence

Android's managed cloud-research path binds the transport source ID to the host-owned group, root run, turn, dispatch, person, round and dependencies before dispatch. The binding is immutable and stored durably without the progress display's cache eviction. It is not inferred from a provider name or text in the model prompt.

The cloud tool execution boundary records the exact input/output JSON, input/output hashes, tool name, execution timestamps and bound identity in an encrypted ledger before returning `galaxyssi_evidence_receipt` to the model. Each observation has an immutable invocation identity and a hash over the stored payload. Reusing an invocation with a changed outcome fails. Failed and unstructured returns are recorded explicitly. Execution exceptions attempt to preserve a failed observation and still propagate without being masked by recording errors. When recording a completed operation fails, its real output is preserved with `galaxyssi_evidence_recording.status=not_durable` and `do_not_reexecute=true`, but no valid receipt. Bookkeeping failure must not automatically repeat a completed side effect. Revoked group access still rejects late output. A result without a durable receipt cannot be referenced as host evidence.

A receipt's `returned` status means a tool returned structured output. It does not mean every source succeeded, a page was fully read, an artifact still exists or a scientific claim was verified. The `research_audit` tool is labeled `member_assessment_recorded`, not an independent test. All records carry `execution_observed_not_claim_verified`. Exact tool observations and model interpretations remain distinct objects.

Workspace publication resolves `observations` against this ledger. Missing IDs, mismatched hashes, corrupt records and inaccessible current independent work reject publication. The host copies the validated references into `host_observations`; model-supplied values for that field are ignored. The workspace revision itself remains `member_reported_not_verified`. Existing research checkpoints retain the receipt with the saved tool output, so restoring the same observation does not require another lookup.

The optional recorder is absent for ordinary non-collaboration chats. Coverage includes Android managed streaming cloud research and explicitly bound native model-loop invocations. Legacy non-streaming paths, native callers without a managed dispatch identity, and authenticated Desktop/Codex result receipts still require explicit adapters. Missing adapters must not be represented as observed evidence.

### Native execution observations

`AgentNativeToolInvocationContext.collaborationSourceMessageId` is supplied by the host, never parsed from model tool arguments or generic attributes. The native recorder resolves the exact immutable source/group/turn binding before assigning member identity. Managed local-model web loops carry this identity from dispatch; registry subsets retain the recorder. Ordinary invocations do not open the collaboration ledger.

Native observations use `origin=android_native_tool` and preserve the complete native result, including execution status, verifier outcome, input/output hashes, tool version, executor provenance and replay information. `verification_failed`, unavailable, rejected, cancelled and timed-out results are failed evidence. A native verifier normally checks the tool contract; it does not certify a scientific claim or satisfy computational/physical goal criteria by itself.

The registry commits any side-effect outcome first, then records collaboration evidence, then returns host-owned `galaxyssi_evidence_receipt` outside executor-controlled output/metadata. Recording failure preserves the actual outcome and provides `galaxyssi_evidence_recording` with no receipt and `do_not_reexecute=true`. Removed or mismatched group bindings cannot issue evidence. This bookkeeping path does not grant tool permissions or revive revoked group membership.

Each observation ID combines the native invocation ID and exact result digest. Re-observing an identical result is idempotent. A registry replay is a distinct observation of the original effect, explicitly marked `replayed`; it is not counted as a new experiment. Same-member retries retain side-effect deduplication, while different managed members have distinct effect scopes even if a model repeats an idempotency key. Unbound existing effect identities are unchanged.

Typed host metadata survives native-result codecs, compact model projection and encrypted loop checkpoints. Checkpoint bindings include the managed source identity, preventing another member from restoring the same loop as its own. Restoring a committed result does not call the tool or recorder again. Exact referenced observations still undergo the ledger's normal access and hash checks before publication or acceptance.

## Goal acceptance checkpoint

An `achieved` assessment is a proposal to finish, not authority to end the goal. Its criteria must already have been established by an earlier plan. Each documentary criterion includes exact `delivery` and `review` references containing `object_id`, `revision` and `sha256`.

The delivery is a substantive saved artifact, proposal or decision. A different person publishes an `acceptance_review` object whose `body.acceptance_review` names the exact criterion ID and requirement, the exact target delivery reference, a `supported` verdict, a rationale and an empty `unresolved` array. Previously stored `decision` objects with this structure remain subject to the same host acceptance checks. Its `parents` must include the reviewed version. Missing, changed, inaccessible, cross-run or superseded revisions fail acceptance. Referenced observations must resolve to durable returned tool output; failed tools and recorded member assessments do not become supporting observations.

Typed review publication checks JSON structure before committing a revision. A string containing `acceptance_review` inside `body.content` is not a review object. Target versions must be integers and identifiers/digests must have the exact expected shape. `supported` cannot coexist with unresolved blockers. Nonblocking improvements belong in a separate `body.recommendations` field and cannot erase unmet requirements. Malformed publications return a durable rejection with a repair reason; new work is needed for a corrected publication, preserving the original report and preventing a retry from overwriting its dispatch. Structural validity is not semantic or scientific verification.

Criteria that depend on a specific kind of original tool evidence can preserve `required_observations: [{"origin":"desktop_codex_tool","tool":"codex.commandExecution"}]`. Supported origins are the ledger's `desktop_codex_tool`, `android_cloud_tool` and `android_native_tool`; tool names must match the recorded tool exactly, including its namespace. Established source requirements can be strengthened, but not removed or replaced during continuation or acceptance. The review's exact `host_observations` must resolve to returned, non-assessment originals of each required origin/tool. A receipt for reading a peer's summary does not satisfy a requirement for the underlying command output. Source matching establishes provenance, not claim relevance, full reading or correctness; those require retrieval checks and qualified semantic/domain validators.

The Android host evaluates these records at the managed member-completion boundary and places a typed acceptance receipt outside the model response text. The receipt binds the assessment, preserved criteria, original goal, root run, turn and coordinator node. It is persisted with the child result and recovered with the execution checkpoint. Text that imitates the receipt is ignored. Truncated or changed output cannot reuse it. Snapshot rendering uses the stored receipt and does not rescan workspace/evidence storage.

This check establishes documentary delivery and independent review of a precise version. It does not certify scientific truth or the relevance/correctness of every sentence. Computational and physical criteria require qualified execution/experimental adapters, not this documentary validator alone. They remain open for actual execution/resource work; they must not be relabeled as documentary or satisfied by simulation. Semantic correctness and domain-specific validation remain explicit limitations; the source-coverage contract below checks completeness and review integrity rather than semantic truth.

An unverified completion returns repair feedback to the coordinator and follows the existing goal-continuation/checkpoint rules rather than publishing a successful final delivery. This does not add a step limit or override pause/stop, permissions or resource-blocker handling. Previously completed records without this gate are retained as `unverified_history`, not retroactively certified and not automatically restarted by upgrade. Every newly created goal, new execution event and continued batch enables the gate.

### Multipart original-goal coverage

Formal completion also requires an exact saved goal mapping and an independent `body.semantic_coverage_review`. Each mapping binds host `goal_sha256`, the full `criteria_sha256` and host source IDs; it cannot substitute a summary, rewritten source text or model-counted offsets. Source slices are mechanical reference units, not a host claim to have interpreted every requirement. Each review names the exact mapping version and explicitly assesses every assigned source ID and criterion association. The evaluating coordinator and mapping contributors cannot certify their own coverage.

Android 1.4.27 accepts either `goal_coverage: {mapping, review}` or `goal_coverage: {parts: [{mapping, review}, ...]}`. Parts can be authored and independently reviewed by different members. All parts bind the same original goal and criteria; their union must cover every source ID exactly once and every criterion at least once. Each part's review is checked independently, including unselected dissent, current versions and contributor ancestry. No fixed total part count is introduced.

Large collections can be saved as `kind=artifact`, `body.semantic_goal_manifest`, with format `galaxyssi.semantic-goal-manifest.v1`, full host goal/criteria hashes, and either `parts` or `manifests` containing exact child references. Each referenced mapping, review or child directory must also appear in `parents`. Completion then references only `goal_coverage: {manifest: exact root reference}`. Empty/mixed directories, repeated branches, cycles, duplicate mappings, stale revisions and foreign-run material fail. Resolution is iterative; all directory versions are rechecked within the same mutation-fenced acceptance operation as their reviews. See [multipart coverage validation](../testing/COLLABORATION_MULTIPART_GOAL_COVERAGE.md).

Original tool observations cited by a selected review retain the separate [host read-coverage contract](../testing/COLLABORATION_EVIDENCE_READ_COVERAGE.md). Full pages served to a scoped member before publication are not proof of provider receipt, comprehension, scientific correctness or successful experimentation.

## Retrieval and removal

Use `galaxyssi.phone.collaboration.recall` with `mode=workspace`:

- Without `object_id`, browse references and follow `next_cursor` until it is absent.
- With `object_id` and `revision`, read the exact immutable object and follow `next_offset` until it is absent.
- Reads return at most 8,000 characters per body page; this is paging, not deletion or a research-step limit.
- The group and turn are taken from the authorized tool context, not supplied by the model.
- The general recall endpoint exposes prior rounds and other turns in that group. Current assigned dependency output is delivered by the scheduler, not by opening access to all independent members.
- An invisible current head does not conceal its earlier visible revision.
- Removing a group revokes reads and writes, removes its stored objects and blocks late publication.

Full originals remain separate from prompt summaries. Hashes are integrity identifiers, not portable signatures or proof that an observation is true. Host tool/source/artifact verification and independently grounded goal acceptance remain separate, unfinished integrations.

For host observations, use `mode=evidence` with `evidence_id` and optional exact `sha256`; omit the ID to page the visible directory. Body paging uses the same `offset`/`next_offset` convention. The recall context may read prior rounds/turns in its group; current dependencies receive their receipts through assigned handoffs. Group deletion revokes bindings and deletes its evidence ledger as well as the workspace.
