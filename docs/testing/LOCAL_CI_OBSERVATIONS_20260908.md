# Local CI Observation Acceptance: 2026-09-08

## Scope

Desktop source version: 1.1.4. Base: `fb7f5b0e8`.
This increment supplies real CI evidence to the local repair Agent and recovers
from typed context-window rejections. It does not replace the independently
verified candidate implementation or imply completion of the overall autonomous
evolution goal. No phone installation or production scheduler activation was
performed for this increment.

## Automated Verification

- 109 focused backend tests passed in 71.339 seconds. Suites cover CI tools,
  bounded subprocess output, implementation context, local planning and context
  recovery, durable observations, CI supervision and repair publication.
- 29 Desktop JavaScript tests passed; Desktop structure checks passed.
- `node tools/dev/check-repo.js` passed, including the Chinese text guard.
- Recovery tests verify original-goal retention, latest-observation retention,
  no repeated write, cancellation, finite history reduction, and rejection of
  generic HTTP errors as context-window signals.

## Actual GitHub And Local Model

The controlled target was [PR #2892](https://github.com/galaxyssi/GalaxySSI/pull/2892),
head `013a98b5a5d2ff2aeb26bea465ee5cc283f4f6d0`, failed Actions job
`101954444995`. The initial direct log read obtained 17,244 redacted characters,
without truncation, with SHA-256
`ab8f10f9672fd23f5eb819260b80863e4ec3fde15eb91bb5d41a9f8f3368c4c9`.

Inference used Qwen3-4B-Instruct-2507 Q8_0, llama.cpp b10839, CPU, an 8,192-token
context and a literal-loopback endpoint. No private model prompt went to a cloud
provider. GitHub requests were host-mediated diagnostic reads.

Two earlier live attempts encountered a PR merge during observation. They
correctly reported a changed target and did not accept stale logs. The final run
used a newly bound, read-only snapshot of the already merged PR. This is not an
exception allowing an old repair task to continue after a merge.

The Chinese diagnostic task independently chose:

1. `ci_checks`: succeeded; model request took 39.156 seconds.
2. `ci_log` without an offset: succeeded; model request took 15.906 seconds.
3. `finish`: diagnosis returned; model request took 313.594 seconds.

These are local CPU model request durations, not phone chat latency or end-to-end
network percentiles. The model correctly identified `ChineseWakePolicy.kt` and
`strings_voice_call.xml` as the files rejected by the Chinese text guard.
Its suggested edits were not executed or independently accepted; diagnostic
success must not be interpreted as repair success.

An earlier head-first log read reached 8,982 input tokens and the server rejected
it against its 8,192-token window. This was a genuine transport error, not a
simulated timeout. The runtime now recognizes the provider's structured context
error, removes older complete observations, and retries without repeating tools.

A separate controlled history-injection test exercised the real local endpoint
and production loop after the fix. Its two initial directory observations were
test-driven; stale evidence was deliberately enlarged. The real server rejected
10,828 tokens against 8,192 in 0.610 seconds. The loop removed one old pair,
retained the goal and latest observation, and the real model returned the correct
empty-directory conclusion in 32.094 seconds. Exactly two directory operations
and one compaction event were recorded. This is transport/recovery acceptance,
not a fully autonomous fault-generation or repair test.

Local raw evidence is retained below `build/` in this worktree, not published as
runtime log content: `ci-log-live.json`, `ci-model-observation-final.json`, and
the failed-run reports. The reusable read-only harness is
`tools/testing/run_ci_log_acceptance.py`. The controlled recovery report is
`build/real-context-recovery.json`; its harness is retained beside it as
`build/verify_real_context_recovery.py`.

## Remaining Boundary

The retained long Chinese candidate already completed independent acceptance and
publication as PR #2892; see
[the retained-candidate report](RETAINED_CANDIDATE_VALIDATION_20260908.md).
This increment verifies the next missing diagnostic capability. It does not
grant success to PR #2892's historical failed CI snapshot. Model-led replanning
for an inherited base failure outside the original candidate scope, publication
of that repair, and acceptance of the integrated goal remain separate work.
