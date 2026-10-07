# Executable Case Acceptance

`executable_tool_cases.v1` connects the existing generated-tool lifecycle to
computational goal acceptance. It is not a second executor, an arbitrary
model-installed validator, or a scientific truth oracle.

## Contract

A coordinator can preserve an input/output suite before the program exists:

```json
{
  "id": "executable_tool_cases.v1",
  "environment": "python-standard-library",
  "purpose": "Check the required transformation",
  "oracle_basis": "Identify how the reference values were obtained",
  "coverage_gaps": "State what the finite suite cannot establish",
  "cases": [
    {"id":"target","purpose":"target","reason":"Requested case","input":{"x":1},"expected":2},
    {"id":"retained","purpose":"regression","reason":"Prior capability","input":{"x":0},"expected":0}
  ]
}
```

The criterion uses `verification=computational`, `evidence_kind=observed` and
the literal requirement:

> Verify a saved executable tool on all preserved test cases in the declared environment; this does not establish general correctness, reference truth or physical validity.

All suite fields are immutable through continuations. Candidates may change;
expected answers and the environment may not be silently weakened. The number
of cases is task-derived, subject to the existing runtime source/output envelope,
not a new research-round limit. JSON objects, arrays, strings, booleans, null and
finite numbers can be tested, not only arithmetic expressions.

## Execution and Acceptance

1. Publish the source as `executable_tool` and a `tool_test_plan` that exactly
   preserves the suite fields and adds the exact source reference.
2. Execute that registered plan through the existing authorized native runtime.
   The host supplies the harness and compares every actual value with its reference.
3. An independent member reads the full original receipt and reviews code,
   oracle, environment and limitations before publishing `tool_release`.
4. Publish a substantive artifact with `body.computation` containing only
   `validator_id` and the exact `tool_release` reference.
5. Delivery and its independent `acceptance_review` both cite the original test
   observation. The reviewer must have read every evidence page before publication.
6. Final acceptance resolves the immutable release, source, test plan and original
   evidence again, verifies dispatch/source/harness identities, and recomputes the
   comparison from recorded actual values. It never executes code during acceptance.

The existing goal mapping, review dissent, original-goal preservation, access
isolation and workspace mutation fence still apply. A program contributor cannot
release or independently accept the same program by wrapping it in someone else's
delivery. A successful run from another goal cannot be used as a current execution.
Reopening the workspace can re-evaluate saved evidence without repeating work.

## Scope and Remaining Gaps

Only `android_native_tool` / `galaxyssi.runtime.execute` host receipts currently
qualify. Generic Desktop shell output and model-written `passed` flags do not.
Remote members must inspect current tool capabilities and delegate to an authorized
phone-runtime member where available. This change does not invent remote execution
permission or provide a Desktop Python verification adapter.

Passing establishes the recorded program's results on the declared finite suite.
It does not prove independent reference truth, held-out generalization, novelty,
transfer, broad correctness, biological function or physical experimentation.
Those remain separate requirements. Do not replace an unsupported original goal
with this easier finite-suite criterion merely to obtain an accepted status.

The original failure records remain in the evidence ledger. Rejected, truncated,
incomplete or mismatched receipts do not become passes. The generated Python
runtime retains its existing authorization and security properties; it is not a
new sandbox for hostile source code.
