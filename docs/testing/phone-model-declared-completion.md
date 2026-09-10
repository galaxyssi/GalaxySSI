# Model-declared phone completion requirements

## Regression

The real phone task created a file, read it back, and calculated its SHA-256.
Codex then returned a correct final answer. The host rejected it because a
substring rule matched the Chinese phrase for committing code inside the user's
explicit instruction not to commit. Repeating the model turn did not fix the
host's interpretation. This blocked ordinary Agent Loop completion after the
parallel worker deadlock was fixed.

## Contract

The supervising model declares the requirements at the ActionPlan root:

```json
{
  "completion_requirements": {
    "publication": "none",
    "phone_linux": false,
    "reason": "The user requested local file verification without publication."
  },
  "actions": []
}
```

This fragment documents the fields only; executable plans still require actions.
Publication is one of `none`, `commit`, `push`, or `pull_request`. `phone_linux`
is a JSON boolean specifying whether successful guest execution is part of the
requested outcome. These are completion obligations, not permission grants.
The model interprets user intent, including exclusions. The host no longer
infers these obligations from goal keywords or a repository URL.

- Omitted declarations inherit the current plan's declaration.
- Malformed declarations are rejected, never silently treated as `none`.
- A missing declaration at final completion returns control to the model.
- Changing the declared outcome requires an explanation. Corrections remain
  possible when the model misunderstood the original request.
- Plans, durable recovery, reviewer prompts, and repair plans retain the values.
- Changed values invalidate cached prompts. Accepted declarations are recorded
  in the connector action's durable parameters.
- Host verification still requires successful structured receipts for requested
  Git publication or phone Linux execution.
- Only a matching, model-marked terminal publication receipt can close without
  another model turn. Generic file/runtime receipts return to model observation.

## Verification scope

Unit coverage includes strict parsing, publication/runtime combinations, rejected
malformed receipts, explicit corrections, inherited declarations, durable
recovery, session isolation, prompt-cache invalidation, and publication-free
negative Chinese goals. The latter uses a supplied model declaration; it does
not by itself prove a real provider will interpret the goal correctly.

Real-device acceptance must use the original Chinese instruction including its
negative publication clauses. It must verify tool receipts, file content and
hash, the model's final answer, and the App's completed state. Building an APK
or seeing a correct provider response alone is not acceptance.

This change does not complete the broader long-cycle, device reboot, external
side-effect, multi-provider, Blob, or multimodal acceptance matrices.

## Recorded acceptance (2026-09-09)

- Android 1.1.36 (922), installed in place on SM-T575. Existing install identity
  and data retained; the attached S26U was not modified.
- Full unit suite: 3,396 tests, zero failures/errors, five skipped, 492 suites.
  The first run exposed two stale prompt-text assertions; the second full run
  passed after updating those assertions to the equivalent compact requirements.
- Repository guard, 73-library AArch64 16 KB audit, and QNN package audit passed.
- Real-device parallel coordinator-monitor regression passed (0.441 seconds).
- Normal App task token: `live-completion-contract-1788967495742`.
- Initial model response explicitly declared `publication=none`,
  `phone_linux=false`; it scheduled write, dependent read, and dependent hash.
- The App executed the tools. A separate read-only ADB check confirmed content
  and SHA-256 `69967de37b8bb2bf7eb89b9c72a3e74e5af30f85380373bedd11b7d10c77a207`.
- The second model response supplied the final answer with the same declaration.
  The App entered `COMPLETED` and displayed an assistant answer. No completion
  repair/publication turn was needed. Exactly two matching Desktop tasks completed.
- App task start to assistant entry: 218,017 ms. This is correctness acceptance,
  not a latency target pass. Transport and model delays remain separate work.

Local evidence is retained under `build/phone-completion-contract-*`: both build
logs, gate logs, device test log, App transcript, provider responses, file proof,
and final screenshot. These public test artifacts are not production user data.
