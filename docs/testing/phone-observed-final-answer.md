# Phone Tool Observation and Final Answers

## Contract

A successful generic native tool receipt is an observation, not a final answer.
Even if the planner sets `completes_goal=true`, the supervised loop returns the
receipt to the model. The model can continue the tool graph, correct a failure,
or return a single `DRAFT_PLAN` action targeting `task-complete` once the existing
evidence proves completion. That action's description is the user-facing final
answer, in the user's language. It must not repeat a completed tool just to end
the task or replace the answer with internal diagnostic fields.

Validated commit, push, and pull-request receipts retain their existing localized
fast-completion path. Failed, pending, malformed, or incomplete publication
receipts cannot use that path. Existing runtime and publication evidence checks
remain in place.

This change uses the existing observation reviewer and completion marker. It
does not introduce a tool-specific response template, a new execution limit,
or a new model provider. ASR, QNN, transport, and Desktop execution are unchanged.

## Regression Coverage

- A successful runtime receipt marked terminal still requires model observation.
- A successful file-read receipt cannot become a raw final answer.
- Failed or pending terminal receipts cannot bypass observation.
- Structured commit, push, and PR completion remains supported.
- Initial and continuation prompts both specify the observed completion contract.

## Device Acceptance

Use the normal Chinese chat entry on SM-T575 to ask the agent to write a unique
small file in its phone workspace, read it back, and report the verified result
in Chinese. Do not create the file from ADB or substitute an instrumentation
result for the model's work. Independently inspect the resulting file and hash
after completion. Record the conversation, local task, Desktop turn IDs, model
observations, final message, and elapsed time in the local test artifacts.

A passing file task is not full acceptance of long-term DAG execution, reboot
recovery, all-provider failover, or the overall performance targets. The extra
model observation may add latency; measure it rather than claim a speedup.

## 2026-09-09 Validation

Android 1.1.34 (920): 3,394 unit tests, zero failures/errors, five existing skips;
repository, 16 KiB alignment, and QNN package gates passed. Installed in place on
SM-T575 without clearing data. Earlier runs exposed prompt-size regressions;
the contract was compacted without raising the existing budgets.

Real task `live-observed-final-1788961888809` created its directory and file,
then blocked before executing the parallel read/hash observations. A JDWP stack
snapshot identified an existing monitor inversion: `acceptConnectorResponse`
holds the Agent monitor while waiting for the batch, and both batch workers wait
on that monitor in `executeAction` when registering cancellation. No final
answer was produced, so device acceptance remains pending the separate
cancellation-lock repair. Local evidence is in
`build/phone-observed-final-thread-dump-socket.log` and
`build/phone-observed-final-live.json`. This is not a passing end-to-end run.
