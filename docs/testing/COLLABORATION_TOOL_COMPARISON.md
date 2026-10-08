# Paired executable tool feedback

`tool_test_comparison` is an immutable, group-scoped research object. It compares
two original native test observations using the existing tool harness and case
validator. It does not execute Python during publication and adds no scheduler,
model defaults, permissions, automatic adoption or goal-acceptance shortcut.

## Contract

```json
{
  "purpose": "Compare the repair against the preserved cases",
  "baseline": {
    "tool_test_plan": {"object_id": "baseline-plan", "revision": 1, "sha256": "exact-hash"},
    "observation": {"evidence_id": "original-baseline-test", "sha256": "exact-hash"}
  },
  "candidate": {
    "tool_test_plan": {"object_id": "candidate-plan", "revision": 1, "sha256": "exact-hash"},
    "observation": {"evidence_id": "original-candidate-test", "sha256": "exact-hash"}
  },
  "interpretation": "Member interpretation, not a host causal conclusion",
  "limitations": "Known coverage and environmental limitations"
}
```

Publish this under `body.tool_test_comparison`, alongside substantive `content`,
and cite both original observations in the usual workspace `observations` array.
Read both originals completely first. The host rechecks the source, compiled
harness, dispatch identity, plan registration time, exit status, report capture,
runtime identity, exact case coverage and actual values. An original can contain
failed cases; a tool release still requires complete passing independent review.

Both observations must be from this goal's group/run/turn. Sources and test-plan
identities may differ, but environment, purpose, oracle basis, coverage gaps and
the complete ordered cases must match. Case IDs, roles, reasons, inputs and
expected values cannot change to hide a regression. Python runtime identities
must also match; this does not certify complete environment equivalence.

The host preserves each original check and reports `improved`, `regressed`,
`both_passed` or `both_failed` per case, plus separate counts. Execution errors
remain failures. Missing/truncated output, nonzero process exit and mismatched
plans reject comparison rather than appearing as zero failures. Cached scores
are not trusted. Exact historical object versions remain available, but comparison
does not approve reuse of a stale tool or grant its permissions.

Members can use these facts to repair further, challenge an oracle, keep multiple
alternatives, or arrange independent validation. The normal release, experiment,
retention, regression and goal-acceptance requirements remain separate. The
comparison is discoverable in scoped evolution and capability recall; its raw
evidence and failed versions remain available after reopening the workspace.

## Verification scope

`CollaborationToolComparisonTest` covers paired improvements and regressions,
first-version ceiling, exceptions, changed cases/oracles/runtimes, missing reads,
wrong digests, duplicate evidence, incomplete reports, cached score substitution,
cross-goal relabeling and persistent idempotent publication.

`CollaborationExecutableToolProcessTest` runs two deliberately imperfect local
Python fixtures through the production harness. One repair fixes a target case
and breaks duplicate preservation; both facts must remain visible. These fixtures
are developer-written synthetic tests, not autonomous methods or real-model
results. Existing release and finite-case acceptance tests guard their stricter
requirements after shared receipt validation is reused.

No result here proves oracle truth, independent attempts, unseen-task transfer,
causal peer contribution, durable capability growth or scientific innovation.
Real App/model adoption and the native-device comparison path remain separate
acceptance work. Private scientific data and papers are not stored in this repo.

## Local result (2026-10-08)

Android source version 1.4.103/1188 compiled successfully. The selected eight JVM
test classes passed 111 tests with zero failures, errors or skips, including six
real local Python process tests. Repository checks and `git diff --check` passed.
The new comparison was not installed on a phone and no real model was called.
This change does not deploy or modify the currently running Desktop instance.
