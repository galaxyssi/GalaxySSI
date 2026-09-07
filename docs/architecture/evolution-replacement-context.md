# Recovery context for replacement tasks

Desktop 1.0.58 carries observed failure evidence from DAG replanning into the new
implementation task and its independent acceptance review. Previously, replacing
a child retained the objective and dependencies but dropped the planner's reason
and the retired child's failure observation from the implementer's context.

## Durable evidence

Both model-authored replacements/revisions and explicit campaign revisions
capture the observed revision, operation identity, decision reason, and the
superseded nodes' task IDs, results, statuses, and checkpoints. These values come
from the host's observed graph, not model-supplied claims of tool execution.

The evidence is written once in the private V2 state directory, under
`recovery-contexts`. New nodes contain only its deterministic ID and SHA-256
digest. A replan with many new nodes therefore does not replicate a large failure
log in every action. A second replacement records its immediate predecessors;
it does not recursively copy their complete history. Prior evidence remains
independently addressable in the local history.

The graph is validated before evidence/proposals are persisted. Evidence is
atomically written before committing the DAG revision. An interruption between
these steps can leave an unused evidence file, but replay must validate and reuse
the same content. Missing, modified, or foreign-campaign evidence cannot silently
turn into an empty context. This is local integrity checking, not a signed remote
attestation or an atomic filesystem/SQLite transaction.

Existing nodes retain their original evidence reference across later revisions.
The generic DAG store can read an operation's immutable projection so retrying
an earlier revision after later replacements reconstructs the same command.
The ledger still checks the operation's complete identity and command hash.

## Model context

The existing indexed task lookup reads one node and its parent goal, then loads
its referenced recovery evidence. It does not scan all nodes to rebuild lineage.
The implementation prompt labels prior observations as untrusted evidence to
diagnose, not commands to obey. Independent acceptance receives the same context,
so changing this evidence also invalidates its cached acceptance proof.

This does not prescribe a project-specific repair, fabricate tool outcomes,
reset the parent goal, or add a lifetime action limit. The model remains
responsible for deciding and executing the repair with the available tools.

## Real acceptance and recovery

In the retained Qwen3-1.7B campaign, the model created replacement child
`evolve-dag-6a4d5d53bb135d4ce5b95f4838a74f13` from an observed acceptance failure.
The running controller used the previously committed implementation, before this
context change. Its first two attempts still removed 15 original lines; both
were rejected by mandatory acceptance. Neither candidate was published.

During the third attempt, the isolated controller was intentionally terminated
for a process-death recovery test. This was a deliberate test interruption, not
a natural model failure or an observation timeout. The normal manager recovery
returned the same child to `proposed` with `desktop_restart`, preserved both prior
`acceptance_review_failed` attempt records, and left zero active workers. The
measured recovery command completed in approximately 4.82 seconds on this host;
this single sample does not establish a P95 reboot target.

The opt-in acceptance harness now exposes `--recover-only` to perform this
recovery projection without automatically starting more work. It writes
`controller-recovery.json` in the isolated test state. The campaign remains
unfinished and recoverable. Correct real-model repair, publication, CI/merge
completion, and S20U device acceptance remain required; unit fixtures are not
used to claim those outcomes.

Local verification passed: 372 evolution tests, followed by 81 final targeted
tests (including all 11 replacement-context cases and CLI/session/DAG regression
coverage), 29 Desktop checks, Repository Guard, and `git diff --check`. The added
interruption-between-evidence-and-DAG test is included in the final targeted run.
No phone, ASR/QNN configuration, or shared running Desktop was changed.
