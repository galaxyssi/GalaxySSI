# Phone planning latency spans

## Scope

Android 1.1.32 adds synchronous planning spans to the existing bounded, asynchronous
latency journal. It does not change routing, task recovery, prompts, native tools,
model settings, ASR, QNN, or transport behavior.

The initial `MobileNativeAgent` planner call opens a task-scoped measurement.
Supervised prompt compilation and `AgentPlanFactory` contribute nested phase
measurements. Ordinary planners still contribute the total and plan phases when
applicable. Continuation paths outside that initial scope are not yet covered.

Each attempt has a separate opaque operation ID, including repeated subphases.
Nested scopes restore their parent, and scopes are not inherited by worker threads.
The journal records hashes, stage names, monotonic times, and outcomes, never goals,
prompts, file paths, model responses, or tool output. Failed/cancelled samples do not
count as successful latency. Diagnostic failures cannot rerun or fail business work.

## Metrics

All phases expose count, incomplete, unsuccessful, P50, P95, and P99 through
`AgentLatencyContract.summarize`:

- `phone_planning_total_ms`: initial planner invocation, including pre-prompt work.
- `phone_planning_progress_ms`: execution-history progress projection.
- `phone_planning_inventory_ms`: stable contract and available tool inventory.
- `phone_planning_goal_ms`: current goal sanitization.
- `phone_planning_context_ms`: durable supervised context.
- `phone_planning_conversation_ms`: conversation transport context.
- `phone_planning_prompt_ms`: cached dynamic prompt assembly.
- `phone_planning_plan_ms`: plan construction and validation.

Nested durations overlap the total. Do not sum them with the total. Match start/end
within the same trace, clock, and operation. Android local task IDs and Desktop
transport task IDs are distinct; cross-host wall-clock subtraction is not a verified
one-way transport latency.

## Validation on 2026-09-09

- Complete local Android unit suite: 3,385 tests, zero failures/errors, five skipped.
  Includes the separate prompt-contract test correction in PR #2952.
- Nine new timing tests cover exact durations, repeated operations, nested scopes,
  thread isolation, cancellation, original exceptions, failed writers/clocks, and
  unscoped or unknown-phase calls.
- Debug APK and instrumentation APK built successfully.
- SM-T575 `R52R90282TY`: in-place installation of 1.1.32 (918), no data reset.
- 73 AArch64 native libraries passed the 16 KB audit; 24 QNN libraries passed the
  package audit (221.68 MiB uncompressed).

### Real normal-entry task

The debug launcher submitted a Chinese request through the normal App submission
flow. Codex reasoned remotely; phone-native tools wrote, read, and checked the hash
of one uniquely named local test file. No fixed or fixture model response was used.

- Case: `live-planning-spans-1788954327365`.
- Local task: `7c39f08f-22af-4fb1-bbf4-df01d72ce073`.
- Final receipt matched a direct ADB file check: 61 bytes, SHA-256
  `391f575bbbc3def581ce8050f5bdfc6697245307552629d59f387ce9936ce814`.
- Initial planning: 2,410.54 ms.
- First progress measurement started 2,379.98 ms after the total started.
- First inventory: 8.50 ms; goal: 1.68 ms; durable context: 1.70 ms;
  conversation: 0.36 ms; prompt assembly: 0.38 ms; plan: 3.16 ms.
- The guarded planner compiled a second cached prompt and plan within the same
  invocation. Separate operation IDs prevented these attempts from being merged.
- App submission to final message: 181,003 ms, not a passing latency target.

This sample does not support optimizing prompt string construction as the primary
cost. Pre-prompt routing/state acquisition requires further instrumentation.
The final message was an English tool receipt despite a Chinese request; user-facing
final synthesis remains incomplete. This is one real sample, not a representative
P95, reboot acceptance, or a complete end-to-end performance gate.

### Re-evaluated previous transport sample

For the earlier final file-task request, existing phone monotonic points show:

- Transport queue to dispatch: 7.03 ms.
- First wire attempt to broker ACK: 792.09 ms.
- Queue to phone-observed peer receipt: 30,253.23 ms.

The last duration includes remote processing and receipt return. It is not proof of
a slow phone queue or a measured one-way network transit. No timeout, retry, or
recovery behavior was changed based on that inference.
