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

Both workspace and evolution directories resolve the tool and test-plan
references nested inside each comparison side. A side is not itself a workspace
reference. Directory and recursive ancestry checks inspect all four dependencies
with their exact kinds. If a dependency no longer has its matching current head,
the comparison requires revalidation without removing its original outcomes.
Tools and plans remain immutable; a new implementation needs a new record. This
directory hint does not adopt or execute a tool.

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

`CollaborationToolComparisonDeviceTest` uses the real encrypted device stores
with synthetic process outputs. It checks paired repair/regression preservation,
complete original failed observations after reopening, cross-group isolation,
receipt replay without another revision, and rejection of unread evidence or
changed expected answers. Each test owns a unique fixture group and removes only
that group and its records. It does not call a model, launch Python, or change
existing conversations, model selection, permissions, or downloaded runtimes.

No result here proves oracle truth, independent attempts, unseen-task transfer,
causal peer contribution, durable capability growth or scientific innovation.
Real App/model adoption and actual native-runtime execution on a phone remain
separate acceptance work. Private scientific data and papers are not stored in
this repo.

## Device regression

Build and install the app and its Android test APK on the explicitly selected
device. Run only the dedicated class:

```text
adb -s <serial> shell am instrument -w -r -e class com.galaxyssi.chat.CollaborationToolComparisonDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

`CollaborationExecutableToolDeviceTest` and `CollaborationMilestoneDeviceTest`
provide adjacent synthetic release/acceptance and publication-receipt coverage.
Do not run the live-model classes as part of this local regression.

## Local result (2026-10-08)

Android source version 1.4.103/1188 compiled successfully. The selected eight JVM
test classes passed 111 tests with zero failures, errors or skips, including six
real local Python process tests. Repository checks and `git diff --check` passed.
The new comparison was not installed on a phone and no real model was called.
This change does not deploy or modify the currently running Desktop instance.

## Device follow-up (2026-10-08)

The first S20U run exposed a directory bug: comparison sides were interpreted as
flat workspace references, throwing `No value for object_id`. Recursive ancestry
validation had the same assumption and could incorrectly label a valid comparison
as requiring revalidation. Both readers now use the typed nested tool/plan links.

Android 1.4.104/1189 was installed on S20U (SM-G9880). All 13 selected device tests
passed: three comparison tests, one executable-tool test, and nine milestone
tests. This includes exact receipt recovery, duplicate publication, paused
assignments, isolated readers, and coordinator admission with occupied workers.
The comparison outputs remain explicitly synthetic, not real model/Python runs.
No existing user conversation or downloaded model was modified by the fixtures.
The running Desktop was not replaced.

The final nine selected JVM classes passed 142 tests with no failures, errors,
or skips, including six local Python process tests. Repository checks and
`git diff --check` passed. The installed base APK digest matches the local APK.

Installed APK SHA-256:
`84953db466ad4f9bef0f247308e92d20442a31f038fe87456126f4bd3b44952f`.
