# Codex Notification Backlog

## Scope

The RPC reader already separated request replies from ordered notifications, but
the notification dispatcher still replayed every queued text fragment through
checkpoint persistence and output callbacks. When those callbacks were slower
than the model stream, the completion notification waited behind obsolete
intermediate snapshots. A wall-clock output throttle does not solve this:
processing a backlog slowly makes each old fragment appear ready to publish.

The dispatcher now drains adjacent, already queued `item/agentMessage/delta`
notifications into one text delta. It never waits to form a batch. Low-volume
live output therefore remains immediately available.

## Preserved Contracts

- Every text character is preserved in provider order.
- Thread, turn, item, phase and all extension fields must match exactly.
- Tool, lifecycle, approval and other notifications are ordering barriers.
- No server request with an `id` is coalesced.
- A bounded batch avoids unbounded concatenation; an oversized input is not
  truncated, and the next notification remains pending in its original order.
- Queue acknowledgements still account for every original entry.
- RPC responses remain on the independent reader path.
- Final output validation, evidence import, receipt confirmation and task
  ownership rules are unchanged.

## Verification

`test_codex_notification_batch.py` covers complete-text reconstruction, a
1,024-fragment backlog, terminal barriers, identity isolation, malformed
identity, Unicode, empty fragments and the batch-size boundary.

`test_codex_startup_concurrency.py` holds a callback while the reader queues
1,024 fragments and a terminal notification. It verifies that an RPC reply can
still arrive, and that releasing the callback delivers one combined text event
followed by completion, instead of replaying every stale partial snapshot.

Run from `apps/desktop/core/galaxyssi-link/backend` with the configured Desktop
Python environment:

```text
python -m unittest test_codex_notification_batch test_codex_startup_concurrency test_codex_conversation_threads test_codex_tool_evidence test_codex_generated_images
```

This is a transport/dispatch regression gate, not evidence of multi-agent
quality gains. Private model trials and manuscript material are stored outside
the repository and are not part of this change.
