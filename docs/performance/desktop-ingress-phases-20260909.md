# Desktop inbound phase timings

Desktop 1.1.37 splits the former receive-to-decrypt interval into measured phases.
The earlier T575 task had 29111 ms between Desktop packet receipt and Signal
decrypt start. That combined interval could not distinguish worker backlog from
route lookup, outer envelope parsing, reassembly or duplicate lookup.

## Contract

| Metric | Boundary |
| --- | --- |
| desktop_ingress_queue_ms | Recorded inbound receipt to handler entry |
| desktop_route_resolve_ms | Handler entry to outer envelope opening |
| desktop_wire_open_ms | Outer authenticated decrypt and JSON parse |
| desktop_wire_prepare_ms | Reassembly, endpoint checks and ciphertext digest |
| desktop_replay_lookup_ms | Ciphertext replay lookup to Signal decrypt start |
| desktop_signal_decrypt_ms | Signal decrypt call |
| desktop_inbound_accept_ms | Envelope validation, durable acceptance and task attribution |

The old desktop_receive_queue_ms is retained with the more accurate UI label
Receive to Signal decrypt. Its boundary is unchanged. All new metrics appear in
the Desktop P50/P95/P99 table, including Chinese labels.

Only authenticated, claimed envelopes with a complete matching task identity
emit these points. Decryption failures, rejected endpoints, duplicate receipts,
and pre-decrypt replays do not become successful task samples. Existing once-per-
task handling prevents duplicate inflation. Unknown identity packets have no task
sample; this is not a complete transport-error distribution.

Timestamps are captured on the Desktop monotonic clock, then attributed after
authentication. No body, secret, path, or plaintext identity is added to the
journal. Diagnostics failure cannot decide message delivery. Signal order,
capacity, retries, encryption, broker endpoints and ACK behavior are unchanged.

Fragmented inputs describe only the completing packet, not the elapsed time
since the first fragment. Direct synchronous callers without a received stamp
have zero queue time. Normal MQTT receipt is stamped after initial topic
resolution; these metrics do not measure the network callback's earlier work.

## Verification

- All MQTT tests: 151 passed, including ten new actual-handler timing tests.
- Expanded timing/recovery/Blob/contact suite: 78 passed; overlaps the ten new
  tests above. Tests use isolated transport/storage doubles, not a real broker.
- Desktop checks: 29 tests and structure check passed; five timing-table tests
  passed separately. Repository guard and diff whitespace checks passed.
- New tests cover exact phase boundaries, privacy, direct callers, rejected
  routes, decrypt failure, endpoint mismatch, ciphertext replay, duplicate claim,
  diagnostic failure, duplicate counting and completing-fragment attribution.

SM-T575 retained Android 1.1.33 (919) and all app data. Desktop was closed normally
after both execution pools were confirmed idle, then started from this worktree.
Its existing Signal Java runtime was reused by explicit environment path; no
pairing or identity reset occurred. The initial test launch lacked that runtime
and failed its live recovery query. After fixing the launch environment, health
reported Signal ready and all ten subscriptions active. A second recovery query
still returned no verified observation in 10.96 seconds; it is NOT a pass.

A normal Chinese model-directed phone task then completed in 207036 ms with three
Codex requests and phone-local tools. Initial request measurements (ms):

| Queue | Route | Outer wire | Prepare | Replay lookup | Signal | Accept |
| --- | --- | --- | --- | --- | --- | --- |
| 0.172 | 11.312 | 0.946 | 84.557 | 41.394 | 53.166 | 47.379 |

Across its three requests, worker queue time was 0.17-0.56 ms. This does NOT prove
the prior 29-second delay fixed: restart and live load differ, and this change
adds instrumentation only. Backlog, recovery timeout, public-network variability,
long-task performance and the English tool-receipt final response remain open.

Test token: live-ingress-timing-1788958597790. Conversation:
87157226-04e7-4e41-a2b8-d0f8d657d22e. Local task:
0ea64d83-16dc-40ea-b5c8-f21e9228a10e. Independent phone file SHA-256:
5ec69cf57b28189ba1f9eb75a0f9a5d8f8a4fac0abcb18d7a63af33f1de86af5.
Raw local evidence: build/desktop-ingress-live.json,
build/desktop-ingress-live-spans-all.json and
build/desktop-ingress-live-metrics-all.json.
