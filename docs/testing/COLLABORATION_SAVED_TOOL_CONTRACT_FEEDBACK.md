# Saved Tool Contract Feedback

## Purpose

A saved document is not automatically a registered executable tool. Members must
be able to distinguish publication, registration, execution and validation. A
rejected record must identify the failed contract rather than report a generic
JSON error or combine unrelated causes into one message.

## Runtime Contract

- Tool code: `workspace.kind=executable_tool`, with `body.executable_tool`.
- Test cases: `workspace.kind=tool_test_plan`, with `body.tool_test_plan` and an
  exact reference to the separately registered tool.
- Independent release review: `workspace.kind=tool_release`, with
  `body.tool_release`, original native evidence and the existing review gates.
- A generic `artifact` can preserve any of these payloads as documentation. Its
  publication receipt includes `registration_notice` when a typed tool payload
  is not registered under its corresponding kind. The host does not relabel it.

The full contract is discoverable through `collaboration_recall` with
`mode=evolution_rules`, `topic=tools`. Remote members use
`collaboration_test_tool` to request the originating phone's existing executor;
local members use `galaxyssi.runtime.execute`. Neither path grants new access.

## Failure Facts

`record_validation` contains a component, code, JSON Pointer, expected value,
actual value and, when applicable, the exact requested reference. It separates:

- Missing or mistyped `body.<kind>`.
- Invalid revision syntax.
- Missing or inaccessible records, without revealing isolated record contents.
- Identity mismatch, digest mismatch, kind mismatch and stale version.

The compact remote status retains these bounded record diagnostics. Original
native receipts remain in the evidence ledger; result checks and arbitrary
stdout are not copied into compact status. Publication drafts and rejected
receipts retain the diagnostics across reopen. The member chooses whether to
repair, investigate or delegate; no retry count or host-selected repair is added.

## Regression Coverage

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*' :app:assembleDebug :app:assembleDebugAndroidTest
```

`CollaborationRecordValidationTest` covers wrong envelopes, exact-reference
failures, isolation, preservation of ordinary artifacts and correct typed
republication. Existing collaboration tests cover release, evidence lineage,
read coverage, runtime compilation and method retention.

On an explicitly selected Android device with the local runtime already
installed, run `CollaborationSavedToolNativeDeviceTest`. It performs two tiny
integer functions, checks a failed and repaired result, rejects a generic test
plan before code execution, verifies the full original diagnostic, and reopens
the durable receipt without automatically rerunning code. It creates and removes
only its own fixture group. It does not download a runtime or call a model.

Desktop regression:

```powershell
cd apps/desktop/core/galaxyssi-link/backend
python -m unittest test_collaboration_tool_test_bridge test_collaboration_milestone_bridge test_collaboration_recall_bridge test_collaboration_publication_recovery test_collaboration_transport_feedback
```

These developer-authored tests demonstrate contract behavior and real executor
plumbing, not autonomous learning, general correctness, novelty or team advantage.
Those claims require separate real-model and held-out task evaluation.
