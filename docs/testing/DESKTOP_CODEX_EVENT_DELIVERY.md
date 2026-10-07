# Desktop Codex Event Delivery

## Durable Boundaries And Stream Heartbeats

Codex notifications are read separately from RPC replies and consumed in order.
Adjacent text fragments with identical thread, turn, item and extension fields
can merge. Item, tool and lifecycle notifications remain ordering barriers.
An interleaved notification can therefore prevent fragment batching even when
the queue contains a large backlog.

Text deltas now use `AgentExecutionHarness.stream_progress`. Every fragment
still updates in-memory progress, elapsed usage and budget enforcement. Only
redundant same-phase progress checkpoint writes coalesce, with a one-second
monotonic interval while fragments keep arriving. The first fragment and phase
changes persist immediately. This is not a task timeout, a research-round limit,
or delayed delivery of the visible text.

Ordinary `progress` remains immediately durable. Item completion, tool evidence,
verification, terminal status, usage accounting and budget failures keep their
existing persistence paths. A crash between heartbeats may lose the latest
subsecond progress timestamp; it does not turn a completed side effect into a
new action or discard an acknowledged tool result. No model output, tool data or
terminal event is removed or moved ahead of an earlier event.

## Content-Free Diagnostics

`Codex event dispatch` log records contain method, thread and turn IDs,
`queue_wait_ms`, `handler_ms`, `batch_entries` and remaining queued entries.
Receipt time is attached before enqueueing; merged batches retain their oldest
receipt. Every terminal event is logged, and slow nonterminal observations are
rate-limited. Prompts, answers, tool outputs and private reasoning are excluded.

Use these observations to distinguish:

- Time before the notification is received from Codex.
- Time queued behind earlier callbacks or persistence.
- Time handling the notification and its downstream callback.
- Subsequent phone delivery and host task settlement.

A provider rollout completion timestamp is not proof that GalaxySSI has already
received `turn/completed`. Do not attribute the entire timestamp difference to
the model, event queue, or an MQTT broker without the relevant observations.
Only the explicit terminal status decides success, as described in the
[official App Server protocol](https://learn.chatgpt.com/docs/app-server).

## Regression Coverage

Run the Python tests from `apps/desktop/core/galaxyssi-link/backend`:

```text
python -m unittest test_codex_stream_checkpoint test_codex_notification_batch test_codex_startup_concurrency test_codex_conversation_threads test_agent_execution_harness test_multitask_isolation test_codex_tool_evidence test_codex_provider_usage test_codex_experiment_boundary test_codex_generated_images test_mqtt_codex_recovery test_mqtt_codex_steering
```

The stream tests cover 1024 interleaved fragments, exact final text, terminal
ordering, independent run state, periodic and phase-boundary writes, restart
readback, and budget failure before the next periodic checkpoint. The dispatcher
tests retain the ten-concurrent-RPC and handler-failure cases, plus receipt-time
and content-free timing-log checks.

Filesystem microbenchmarks are synthetic, not real-model or end-to-end latency
claims. A fresh device trial must still verify completion delivery before this
optimization is described as resolving a previously observed live delay.
