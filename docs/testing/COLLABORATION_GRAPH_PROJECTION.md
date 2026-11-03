# Stable collaboration graph projection

## Failure

Research execution normalizes member roles and assignments at startup. A stored
checkpoint can still contain unnormalized fields, especially after a goal round
creates new assignments. Live graph expansion previously called validation but
discarded the returned normalized members. The lower-level append-only guard
then rejected the different role/context as an attempt to rewrite an existing
child, before that child could be dispatched.

Truncating after trimming also introduced trailing whitespace when the cut fell
on a space. A subsequent trim changed the same member again. A role's formatting
must not stop independent work or be mistaken for a task identity change.

## Correction

- Apply the same validated member projection to startup and every live expansion.
- Trim the end again after the existing role/assignment length bound, making
  normalization idempotent.
- Use the canonical projection for child plans, dispatch member lookup and the
  current execution checkpoint.
- Do not overwrite stored original assignments, results, work signatures or
  evidence merely to normalize their runtime view.

The lower-level immutable-child guard is unchanged. Actual task, authority,
identity and admitted dependency changes remain rejected. This does not weaken
goal acceptance, alter model selection or change collaboration planning policy.

## Regression coverage

`AgentTeamLiveGraphIntegrationTest` covers role/assignment truncation at a space,
old checkpoint whitespace, and encrypted-codec reopen with completed side effects
that must not run again. Existing live expansion and dependency-rebinding suites
retain their negative mutation tests. The device fixture
`CollaborationLiveGraphDeviceTest#roleTruncationRemainsStableAfterEncryptedCheckpointReopen`
uses local synthetic work only and does not invoke a model or physical tool.

Passing these tests establishes scheduling behavior, not learning, scientific
innovation or superiority over a single Agent.

## Verified build

Android 1.4.124 (1209): 75 focused JVM tests passed with no failures or skips.
Both debug APKs built. Four test executions passed on an SM-G9880, covering
normalization after encrypted-checkpoint reopen, live independent review, and
seed/recovery in distinct App processes without replaying completed work.
These device tests used synthetic local data, not real model calls.
