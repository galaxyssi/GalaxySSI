# Indexed physical broker capacity

## Scope and evidence

Desktop code version 1.1.42. Android remains 1.1.43 (929).

After the real late-observation case in PR #2969, read-only production queue
inspection found 5,240 ordinary published rows at attempt 1, plus smaller groups
of retries and other priorities. These rows still await authenticated peer
receipts, but PUBACK has already released their physical MQTT capacity.

The previous `outbound_inflight_count(awaiting_broker_only=True)` nevertheless
selected all sending/published rows and decrypted every route before excluding
application receipt debt. This ran under the delivery lock and repeatedly inside
outbound scheduling. Existing same-clock traces showed approximately two-second
enqueue/dispatch work and a roughly nine-second ingress queue interval, while
many actual broker acknowledgements took approximately 0.28 seconds. These are
evidence of separate bottlenecks, not proof that the entire 40.895-second recovery
duration belongs to this one function.

## Change

- Add a `(status, client_route_id)` index without clearing or rewriting messages.
- Count currently owned physical messages with exact primary-key lookups.
- Inspect only `sending` rows for recent orphaned sends whose retry timer still
  protects capacity after process-local registration is lost.
- Compare sealed route keys directly. No receipt-backlog route decryption is
  needed for physical capacity.
- Preserve row priorities, reservation priority after early peer receipt, route
  isolation, broker ownership beyond retry deadlines, and legacy application
  receipt counting when `awaiting_broker_only=False`.
- Keep all existing global/per-route/reserved/artifact capacity limits and retry
  rules unchanged. No queues, pairings, keys, chats or model results were cleared.

## Automated validation

Two new regression assertions failed before the implementation: 20,002 route
decryptions for a 20,000-receipt backlog, and a full-table scan rather than a
status-index search. Seven new tests now cover the large backlog, index use,
orphan timers, explicit physical owners, early receipt, priority resolution,
route filters and legacy counting.

The combined suite passed 157 tests: encrypted database initialization and
concurrency, durable delivery, batching, capacity reserves, broker ACK ownership,
callback registration, inbound route ordering, fragmentation, timing, recovery
priorities and logical result outbox behavior. Desktop check passed 29 tests
plus structure validation. Repository guard passed.

The isolated algorithm comparison used the same SQLite database and index for
both implementations, real encrypted route identifiers, and placeholder payload
columns that neither algorithm reads. Three samples per condition:

| Published receipt rows | Previous capacity count (ms) | Indexed count (ms) |
| --- | --- | --- |
| 5,240 | 1556.553 / 3111.546 / 6733.921 | 3.965 / 4.234 / 6.267 |
| 20,000 | 17166.801 / 7730.902 / 15101.224 | 4.397 / 4.586 / 6.031 |

All samples counted the same two actual owners/orphaned sends. The old function
was extracted from parent commit `eb5d072e1`; both ran against synthetic temporary
storage, never the production database. This is a local algorithm comparison,
not network latency, P95, or a full end-to-end speedup claim. Host load varied.

Local logs: `build/broker-capacity-index-before.log`,
`build/broker-capacity-index-verified-tests.log`,
`build/broker-capacity-algorithm-probe.log`,
`build/broker-capacity-desktop-check.log`, and
`build/broker-capacity-index-repo.log`.

## Pending real-device acceptance

The running Desktop has not yet been replaced: automatic window launch was
previously denied by execution policy, so the live process was left intact rather
than closed without a confirmed way to reopen it. Manual restart into this
worktree was requested. After restart, repeat the actual Codex final-drop,
process-death/headless inbox recovery, exact-one UI recreation, and plain cold
launch harness on SM-T575 without clearing the existing backlog. Verify the
original body hash and one task attempt/generation, and compare stage spans.

This scoped change does not complete device-reboot recovery, all execution paths,
the full chaos matrix, or the overall long-running Agent goal.
