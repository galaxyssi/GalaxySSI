# Establishing a Missing Verification Route

## Scope

An open computational criterion can initially lack a qualified validator. The
previous continuation rule treated absence as a permanently immutable binding,
so even an applicable existing validator could never be selected later.

A coordinator can now establish that missing binding in a `decision=continue`
assessment. This reuses the existing goal checkpoint and registered validators;
it does not introduce a domain-specific solver or a second execution loop.

## Admission

Both saved and proposed criteria must be open, computational, and observed, with
empty evidence and no delivery or review reference. The ID and requirement stay
identical, all required source obligations remain, and the selected validator
must accept the literal scope of that requirement and its full specification.

The existing atomic continuation stores the binding before dispatching new work.
One invalid criterion rejects the entire plan, including unrelated assignments,
recruitment and resource jobs. After establishment, the bound inputs remain
immutable across continuation and recovery. The semantic coverage hash changes,
so an earlier coverage review cannot silently certify the new contract.

Final acceptance still uses strict binding equality. An `achieved` or `blocked`
assessment cannot establish a missing route; a newly bound route is not a passed
computation. Wrong results, missing originals, independent-review failures and
all existing goal-acceptance checks continue to fail.

## Limits

- This selects an already qualified host method; arbitrary model-written
  validators cannot register themselves or self-certify success.
- It does not replace a broad scientific/physical requirement with a finite
  case suite, change a goal, or qualify simulations as physical evidence.
- Registration occurs before acceptance, not necessarily before measurements.
  It does not establish scientific preregistration, oracle truth, unseen-case
  generalization, held-out testing or learning.
- A general independently qualified external verification adapter remains
  separate work. The three existing computational domains are unchanged.
- No model, paid service, background worker or additional permission is added.

## Verification

`CollaborationVerificationEstablishmentTest` covers the three existing route
types, missing versus malformed bindings, rejected scope/identity changes,
unchanged source obligations, claimed evidence and incorrect computations.
`CollaborationSemanticGoalLoopTest` covers persisted establishment and real work
planning, later rebinding rejection, completion/blocked rejection and atomic
whole-plan rejection. Existing acceptance, semantic coverage, numeric/tool
execution, cancellation and recovery tests remain relevant regressions.

Tests are local JVM coverage, not real-model or phone acceptance. Run results
and deployment scope must be reported separately.

### Local result, 2026-10-10

Android source version is 1.4.127/1212. The collaboration regression selection
passed 1,489 tests in 124 XML suites with zero failures, errors or skips. It
includes `Collaboration*`, `AgentCollaborationRuntimeTest`,
`AgentTeamLiveGraphIntegrationTest` and `AgentSubagentAdmissionOrderTest`.
Kotlin source-size and `git diff --check` also passed.

An initial fixture omitted an active worker's completion; the projection
correctly refused to advance. The corrected test now verifies both refusal
while that worker is active and immutable binding after all workers finish.
No production lifecycle guard was weakened.

The JVM run excluded `:app:buildNativeMemory` and used
`-Pgalaxyssi.requireEmbeddedRuntime=false`. No APK packaging, installation,
physical restart/network acceptance or real-model improvement is claimed.
Desktop source and the completed frozen experiment are unchanged.
