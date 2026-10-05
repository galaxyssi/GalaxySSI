# Structured Tool Failure Feedback

Android 1.4.61 / 1146. This increment improves the existing saved-tool runtime,
not the scheduler, permissions, model defaults or UI. It adds no retry-count rule.

## Contract

The original tool receipt retains the parsed report and full expected/actual test
values. Its evaluation now exposes structured `problems`:

- A stable observed error code distinguishes process exit, parse failure, wrong
  object/format, runtime identity, case coverage, execution errors and value/type
  mismatches. A parsed object rejected by the contract is not called invalid JSON.
- `path` is a JSON Pointer into the returned report, with escaped object keys.
  Process exit uses `/exit_code` in the receipt.
- Case failures include `case_id`. Each mismatching case identifies its first
  difference, not a claim that no other differences exist. Full values are retained.
- Array lengths and missing/unexpected/duplicate case IDs are concrete facts, not
  hidden acceptance caps. Missing output is distinct from explicit JSON null.
- `cause=not_diagnosed` keeps host observations separate from agent diagnosis.
- Runtime capture preserves known original and captured character counts through
  repeated bounding. Truncated stdout cannot become a passing report, even if its
  prefix is valid JSON. It is reported as `report_stdout_truncated`, not a syntax
  error. The existing 512 Ki-character capture boundary is not removed.
- Captured stdout/stderr hashes and parse status are recorded. Existing model
  excerpts retain truncation/count metadata. Complete parsed test values remain
  in the receipt, but bytes already omitted by capture cannot be reconstructed;
  hashes do not imply that complete uncaptured output has been archived.
- Parser exception previews are bounded and labelled rather than duplicating a
  potentially long malformed stream into the diagnosis.

The existing failure index exposes the first structured error code/path so a
member can decide which original evidence to recall. It does not scan successes,
poll a provider, retry execution, change task state or discard failure history.
Repair, delegation and replanning remain agent decisions subject to existing
authorization. A later pass does not erase a previous failed observation.

## Verification Scope

Focused local coverage includes exact paths, pointer escaping, null/missing
distinction, malformed/trailing output, valid-but-wrong schemas, nonzero exits,
duplicate/missing/unregistered cases, twelve registered results, preserved errors,
release rejection and reopening original failure evidence. Existing real local
Python fixtures exercise incorrect code and exceptions, plus normal release/reuse.

The device fixture uses synthetic reports with real encrypted storage and dispatch
binding. It does not execute Python in the phone Linux guest or call a model.

This is more informative host feedback, not evidence that agents autonomously
diagnose all unknown failures or that multi-agent research outperforms a matched
single agent. Real model repair and cross-task transfer remain separate empirical
validation. Manuscripts, private experimental prompts, rubrics and data are not
part of this change.

## Commands

```powershell
$env:GALAXYSSI_TEST_PYTHON='<local Python executable>'
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.CollaborationToolFeedbackTest' --tests 'com.galaxyssi.chat.CollaborationExecutableToolTest' --tests 'com.galaxyssi.chat.CollaborationExecutableToolProcessTest' --tests 'com.galaxyssi.chat.CollaborationCapabilityDiagnosisTest' -x :app:buildNativeMemory --console=plain
```

The native-memory exclusion reuses the existing local native build artifact; it
does not validate a fresh Rust build.

## Verified Outcomes

- 1,042 collaboration, team, subagent, on-device runtime and skill-runtime unit
  tests passed, including 17 feedback tests and four real local Python fixtures.
- 134 additional runtime regression tests passed.
- Main and instrumentation debug APKs built successfully. Android 1.4.61 / 1146
  was installed on the authorized SM-S9480 without clearing application data.
- `CollaborationExecutableToolDeviceTest` passed on that device: synthetic
  truncation and mismatch diagnostics, encrypted failed-evidence reopening,
  later successful release/reuse, and exact member/turn dispatch binding.
- Fifteen existing Desktop evidence-recall regressions passed. Three expected
  unavailable-recall exceptions were negative fixtures, not live model failures.
- Kotlin source-size and whitespace checks passed. No new model calls were made.

The local Python repair fixture supplies the corrected source explicitly. It is
not an autonomous model-repair experiment, and the device fixture is not a phone
Linux execution benchmark.
