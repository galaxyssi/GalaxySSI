# Agent stage latency investigation, 2026-10-26

## Acceptance status

**Not achieved:** the requested target is less than 1 second for each of request
preparation/start, complete Agent execution, and result delivery/display. This
change reduces avoidable framework work; it does not guarantee provider inference
latency or replace complete replies with first-token measurements.

Android 0.1.6.27 (1403) was installed over the existing S26 Ultra application.
Desktop 0.1.6.8 was restarted with the existing data directory. Chat, pairing,
models, and task data were retained. Model selection, reasoning effort, prompt
semantics, encryption, SQLite FULL synchronization, and commit-before-display
ordering were not relaxed.

## Changes

- Cache authenticated Android row plaintext only after checking the current
  database envelope. Bound the cache to 256 entries and 2 Mi characters, with a
  30-second TTL, lifecycle clearing, and overwriteable plaintext arrays.
- Fence cache publication across writes, rollbacks, nested transactions, database
  changes, and concurrent sensitive-cache clearing. Bypass the cache for reads
  inside transactions and for segmented memory or plaintext news storage.
- Restrict Desktop history payload decoding to the requested conversation while
  preserving the original global recent-task window and session isolation.
- Wake the outbound worker after durable PUBACK updates. Packet wakeups do not
  repeatedly run recovery scans; recovery keeps its maintenance cadence.
- Persist all selected outbound attempts in one transaction before publishing
  any packet, retaining retry durability and immutable ciphertext.
- Reuse a loaded Codex thread without waiting on unrelated lifecycle RPCs; fence
  eviction before releasing the state lock. Add content-free RPC timing logs.
- Correct delayed trace markers' wall-clock timestamps from their monotonic
  event times. Expose user-send-to-complete-display separately from first output.
- Extend `tools/dev/measure-agent-reply-latency.ps1` with stage measurements,
  clock-sampling uncertainty, legacy timestamp rejection, and explicit acceptance.

## Real-device samples

S26 Ultra SM-S9480, Android 17; real Codex provider and public MQTT transport.
The Chinese test request asked for a short confirmation without web or tool use.
The same request was used for all samples. These are individual observations,
not a P95/P99 benchmark or a guaranteed speedup.

| Sample | Send to Agent start | Complete Agent execution | Completion to display | Total |
| --- | ---: | ---: | ---: | ---: |
| Before, Android 0.1.6.26 | Not directly comparable* | 9.854 s | 3.357 s | 18.824 s |
| After A, cold App following instrumentation | 8.037 s | 7.686 s | 4.865 s | 20.587 s |
| After B, warm App, same conversation/new turn | 4.542 s | 6.683 s | 3.180 s | 14.404 s |
| After C, warm App, new conversation | 4.208 s | 7.351 s | 2.803 s | 14.362 s |

*Old deferred start markers used the time they were written as wall time. Their
monotonic total remains valid, but subtracting timestamps across devices does
not directly measure the first stage. The reporter now rejects these boundaries.

Cross-device values use phone/PC wall-clock sampling near each request; sampling
uncertainty was approximately 22-32 ms per after sample. Same-device spans use
monotonic time. Do not recompute historical cross-device results using a later
clock sample without accounting for clock drift.

Latest warm sample C, milliseconds:

| Substage | Duration |
| --- | ---: |
| Phone preparation before queueing | 1545 |
| Desktop intake before Agent execution | 1120 |
| Model submission | 1025 |
| Model submission to first output (not completion) | 6008 |
| Desktop completion to wire publication | 756 |
| Outbound queue | 102 |
| MQTT broker acknowledgement | 371 |
| Wire publication to phone receipt, estimated | 333 |
| Phone receipt to accepted result | 451 |
| Accepted result to finalization | 376 |
| Phone receipt to visible completed reply | 1715 |

Some substages overlap; they must not all be summed. In sample C, the last stage
is approximately 756 + 333 + 1715 ms. A broker acknowledgement is not evidence of
phone display. No sample satisfies the three-stage 1-second target.

## Verification

- Desktop final focused regression suite: 121 tests passed across task history,
  tracing, startup concurrency, routing, outbound scheduling, and durable MQTT.
- Android targeted unit suite: 52 tests passed across latency tracing, row cache,
  preference cache, lifecycle clearing, reply commit, and transcript decode cache.
- `assembleDebug` and `assembleDebugAndroidTest`: successful.
- New real-device row-cache suite: 10 tests passed, including Keystore encryption,
  AAD/ciphertext changes, deletion, transactions, rollback, and lifecycle clearing.
- Existing storage, workspace commit, and latency journal device tests: passed.
- A 17,408-character row microbenchmark, 13 samples: median cold read/decrypt
  4.82 ms, warm read 0.62 ms. This is a row-level result, not whole-turn latency.
- An initial combined run had one collapsed-process-row test failure; that test
  passed in isolation. A later full run reached 23 passing tests and four UI
  hydration failures while the phone was locked. Do not count that locked-screen
  run as successful UI acceptance; foreground completion-state verification must
  be repeated with the device unlocked.

## Remaining work

Request preparation/intake and Android result persistence/rendering remain above
budget. Profile their actual critical paths before moving work or changing
transaction boundaries. Provider submission and full answer generation also
remain above 1 second in these samples. Do not silently downgrade the selected
model, skip verification, acknowledge before commit, or truncate answers to make
the metric pass. A larger cold/warm and failure-recovery matrix is required before
claiming a product latency SLA.
