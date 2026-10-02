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

Ready nodes execute under the existing concurrency and authority controls. Failure skips success-dependent nodes while terminal-policy diagnostics can continue. Independent branches need not wait for unrelated slow work. The final coordinator assessment still waits for the declared graph; appending new nodes while that graph is running is not implemented by this version.

## Research object publication

An optional `workspace` array extends `galaxyssi.research-artifact.v1`. Each entry contains:

| Field | Meaning |
| --- | --- |
| `id` | Stable local ID for a new object, up to 160 characters. |
| `object_id` | Existing host-assigned ID for an update; empty for a new object. |
| `base_revision` | Exact expected head revision; zero when creating. |
| `kind` | `hypothesis`, `evidence`, `counterexample`, `proposal`, `experiment`, `artifact`, `decision` or `question`. |
| `title` | Nonempty title, up to 240 characters. |
| `body` | Nonempty JSON object preserving the substantive original content. |
| `parents` | Exact `{object_id, revision}` references used to derive this version. |
| `resolves` | Exact references to preserved counterexamples or questions being addressed. |
| `observations` | Exact `{evidence_id, sha256}` references copied from host tool receipts. |

New object IDs are derived from the group, author and local ID. Group, run, turn, member, dispatch, round, timestamp, revision, previous hash and current hash are host-owned fields. Object kinds are immutable. Current independent work cannot be overwritten or read by an unrelated member. Reference targets must exist and be visible to the assignment.

All updates in one publication are validated before any revision is committed. A stale base revision rejects the complete publication. Revisions, head indexes and publication receipts commit atomically in encrypted storage. A dispatch can replay its identical publication, but cannot publish a different result under the same identity. Corrections require new work and an explicit new revision. Storage errors propagate instead of reporting a successful publication.

The host removes any member-supplied `workspace_receipt` before attaching the actual receipt. A recorded receipt establishes authorship and version integrity only. Objects are labeled `member_reported_not_verified`; neither an `outcome` field nor an independent member's agreement establishes scientific truth.

## Host-observed tool evidence

Android's managed cloud-research path binds the transport source ID to the host-owned group, root run, turn, dispatch, person, round and dependencies before dispatch. The binding is immutable and stored durably without the progress display's cache eviction. It is not inferred from a provider name or text in the model prompt.

The cloud tool execution boundary records the exact input/output JSON, input/output hashes, tool name, execution timestamps and bound identity in an encrypted ledger before returning `galaxyssi_evidence_receipt` to the model. Each observation has an immutable invocation identity and a hash over the stored payload. Reusing an invocation with a changed outcome fails. Failed and unstructured returns are recorded explicitly. Execution exceptions attempt to preserve a failed observation and still propagate without being masked by recording errors. When recording a completed operation fails, its real output is preserved with `galaxyssi_evidence_recording.status=not_durable` and `do_not_reexecute=true`, but no valid receipt. Bookkeeping failure must not automatically repeat a completed side effect. Revoked group access still rejects late output. A result without a durable receipt cannot be referenced as host evidence.

A receipt's `returned` status means a tool returned structured output. It does not mean every source succeeded, a page was fully read, an artifact still exists or a scientific claim was verified. The `research_audit` tool is labeled `member_assessment_recorded`, not an independent test. All records carry `execution_observed_not_claim_verified`. Exact tool observations and model interpretations remain distinct objects.

Workspace publication resolves `observations` against this ledger. Missing IDs, mismatched hashes, corrupt records and inaccessible current independent work reject publication. The host copies the validated references into `host_observations`; model-supplied values for that field are ignored. The workspace revision itself remains `member_reported_not_verified`. Existing research checkpoints retain the receipt with the saved tool output, so restoring the same observation does not require another lookup.

The optional recorder is absent for ordinary non-collaboration chats. These changes currently cover Android managed streaming cloud research and the tools it actually executes. Native-tool registry observations, legacy non-streaming paths and authenticated Desktop/Codex result receipts still require explicit adapters. Missing adapters must not be represented as observed evidence.

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
