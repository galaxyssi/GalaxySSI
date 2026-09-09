# Phone dependent tool graphs

## Real failure reproduced

On SM-T575, Android 1.1.29, a Chinese local-file task was sent through the normal
App submission path to a paired Desktop Codex reasoning provider. The goal asked
the phone to write a UTF-8 file and read it back. It did not ask Desktop to execute
commands. The test used a unique public fixture namespace, not user documents.

The model proposed `workspace.file.write.text`, followed by
`workspace.file.read.text` with a dependency on the write. Logcat recorded:

- One `supervised_plan_rejected stage=action_plan`: the native read included
  `use_outputs_from`, which is supported for connector handoffs, not native input
  substitution.
- Three `supervised_plan_rejected stage=action_batch`: the corrected dependency
  graph parsed, but the batch admission policy required every action to have no
  dependencies. The prompt explicitly allowed dependent actions.

The unchanged graph was repeatedly returned because format repair did not send
the rejection stage to the model. Eventually the model split the work into
separate responses. The App completed approximately 309 seconds after submission.
ADB confirmed the 58-byte file and its SHA-256 matched the tool receipt. This was
a real provider result, not an injected successful executor callback.

## Contract

- A model response contains a topologically ordered graph of phone tool actions.
  Prompt, supervised parser settings, and admission now agree on 64 actions per
  response; the previous parser capped at 12 and its ordinary default was 8.
- `depends_on` references earlier action IDs. The existing execution scheduler
  waits for successful predecessor receipts; failure does not release dependents.
- Every unordered pair must be independent read-only work or disjoint scoped
  resources. Check transitive ancestors, not just adjacent dependency layers:
  a sibling can conflict with a later descendant.
- Registered tools with global effects can run in explicitly ordered chains;
  they cannot run speculatively alongside unrelated actions.
- Do not guess native arguments from `use_outputs_from`. When a later argument
  requires interpreting a result, end the batch and let the model observe it.
- Format repair includes the actual rejection stage and batch reason, without
  logging file contents or credentials.
- A per-response graph bound controls payload and scheduling size, not the
  lifetime number of actions or replans.
- A terminal action must be last and transitively depend on all earlier actions;
  a successful sibling cannot complete a graph with unfinished work.

## Verification

Focused regression tests cover ordered writes and reads, repeated verification,
transitive dependencies, same/nested path conflicts, cross-layer conflicts,
invalid graph identities, exclusive effects, output handoff rejection, successful
dependency release, and failed-dependency blocking.

Android 1.1.31 (917) validation on 2026-09-09:

- 122 focused JVM tests passed, including real-response-shaped parser/remapping
  tests and the existing prompt-size gates (not relaxed).
- 186 core Android JVM regressions passed.
- 24 SM-T575 instrumentation tests passed in 76.272 seconds: continuous replanning,
  workspace identity, durable node journals, and terminal recovery eligibility.
- APK and instrumentation APK builds passed; 73 native libraries passed the 16 KB
  audit, and all 24 required QNN libraries passed the package audit.
- Data-preserving APK replacement kept the existing installation and pairing.

Final APK SHA-256:
`9c782e5368c4a90aa8516c68271b47db404c0b98c056ef1bffc4173f80e58e43`.

## Live observations

The first post-fix APK (before prompt compaction) completed the same class of
Chinese write/read task in 117.860 seconds with zero format repairs, versus
308.975 seconds and four repairs on 1.1.29. The first model graph contained a
native create followed by a dependent read and was accepted directly. Codex then
requested an additional verification read. The resulting 58-byte file matched
the App receipt and an independent ADB SHA-256 check.

After force-stopping the App, a Chinese follow-up in the same conversation asked
the model to read the original file, append a specified suffix into a separate
file, and read it back. It completed in 171.074 seconds with zero format repairs.
The conversation and workspace IDs were retained, the original SHA-256 remained
unchanged, and the new 82-byte file contained the original text plus the suffix.
The test did not give the model the original content in the follow-up prompt.

The final compact-prompt APK was installed and tested again with a fresh Chinese
write/read goal. It completed in 165.102 seconds with zero format repairs. The
initial write/dependent-read graph was accepted directly, followed by a
model-requested verification read. ADB verified the 58-byte result and SHA-256
`eefe211fa1ab3a17a3519624e8db8e478aa3e219feb660dac90e24eaf874381c`.

For that final run, existing App transcript and Desktop task timestamps divide
the latency as follows (wall-clock measurements on these hosts, not synchronized
distributed spans):

| Interval | Seconds |
| --- | ---: |
| App debug submission timestamp to first Desktop task start | 40.821 |
| First Desktop Codex task | 49.419 |
| First task completion to second task start, including phone effects | 18.149 |
| Second Desktop Codex task | 34.794 |
| Second task completion to App final transcript entry | 21.919 |
| Total | 165.102 |

The remaining transport/dispatch and model-review costs need separate tracing
and optimization. Removing format repairs does not establish the latency SLA.

These are single-run timings, not a P95 latency claim. They establish real Codex
planning with phone-native effects and continuation after App process recreation;
they do not establish uninterrupted in-flight reboot recovery, a month-long DAG,
or exactly-once external publication. Human-readable final summaries also remain
a separate issue: the App currently returns a raw successful tool receipt.
