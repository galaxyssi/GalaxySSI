# Execution Feedback in Remote Collaboration Pilots

Android 1.4.62 / 1147. This opt-in instrumentation facility connects the existing
three-node remote pilot to an external executable evaluator. It is test-only;
ordinary collaboration, model selection, tools, retry policy and UI are unchanged.

The operator supplies `remotePilotFeedbackEvaluatorSha256` alongside the existing
frozen-protocol and explicit authorization arguments. After each draft and review,
the fixture atomically writes the complete original artifact to an exchange file.
It waits within the existing slot deadline for evaluator feedback before the next
member is dispatched. The original member output is never replaced by the test
report. The final artifact remains available for a separate held-out evaluation.

Each request binds pilot, slot, node, protocol hash, evaluator hash and exact output
hash. A response must name the exact request and evaluator hashes. Changed output,
foreign scope, duplicates, missing feedback and oversized envelopes fail explicitly;
they cannot silently authorize the next model request. Feedback is labelled as
untrusted observed evidence, not instructions or proof of evaluator correctness.
The prepared-prompt hash includes the actual feedback delivered to the member.

External files use the following names beneath the App external files directory:

```text
feedback-<pilot>-<slot>-<draft|review>.request.json
feedback-<pilot>-<slot>-<draft|review>.response.json
```

Publish the response through a temporary file and an atomic rename. Never overwrite
an existing exchange with a different result or restart a model task because a host
observation timed out. Consult the original test handle, terminal report and cleanup
state. The instrumentation report retains accepted feedback; private evaluators must
retain their own exact input and output files as well.

## Validity Boundaries

- A declared hash binds bytes; it does not authenticate a remote evaluator or prove
  that its tests are sufficient. An independent audit must check actual execution.
- Both experimental arms need the same feedback policy, initial task and planned
  opportunities. This facility does not establish equal provider cost.
- A seeded-fault repair is not proof of discovering unknown faults, innovation,
  skill retention, production phone Linux execution or multi-agent superiority.
- Manuscripts, private protocols, hidden cases, model outputs and reports remain
  outside the repository. Only generic synthetic contracts belong in this PR.

## Local Checks

`CollaborationPilotExecutionFeedbackTest` covers original output retention, exact
hash binding, both prior observations reaching the final node, foreign scope and
evaluator rejection, duplicate/missing exchanges, truncated dependencies and limits.
`CollaborationRemotePilotTest` checks the actual dispatched prompt hash includes the
observations while retaining the existing model-selection and dispatch controls.

The final local snapshot passed 34 focused pilot/artifact unit tests and built
both debug APKs. Native-memory compilation reused the existing local artifact;
the embedded-runtime requirement was disabled for this local debug build.
These outcomes do not establish that an external evaluation improves model quality.
