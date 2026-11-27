# Android #3045: connect OS network changes to MQTT metric epochs

Reference: Android #3045, merge `d31829d8d047abb457cc3b67c5ea68eeb729b94f`,
`GalaxySSIMqttClient.networkAvailable(network.toString())`,
`MqttPoolTransport.networkAvailable` and `MqttMultipathPolicy.setNetwork`.
This follow-up remains on the same formal iOS PR as offline lifecycle and path
diagnostics. Parent increment: `4c2c22aed`.

## Production wiring

Previously iOS exposed `setNetwork`, but only a synthetic test invoked it. Live
network changes could retain RTT, peer-confirmed delivery summaries and chunk
throughput observations from a different network. An available socket or broker
generation does not identify the network on which a latency sample began.

Each running connection pool now owns one additional NWPathMonitor dedicated to
metric invalidation. It compares the previous and new Network-framework NWPath
values on the monitor's serial queue, ignoring equal callbacks. The first
observation is conservatively treated as a change. No network name, address,
gateway, interface identity or path description is copied, logged or persisted.
The policy receives a fresh opaque token, not a serialized OS path.

The observer is replaced/cancelled on pool configuration changes and cancelled
on disconnect/deinit. Its callback hops to the pool queue and checks running,
observer object identity and the captured configuration before resetting metrics.
Even a custom factory reusing the same observer cannot authorize an old
configuration's queued callback. Default factories create a fresh native monitor.
Equal-path filtering is in the native adapter, not inferred by synthetic tests.

This monitor never authorizes sockets, subscriptions, route readiness, messages
or delivery. Existing per-path availability monitors still own connection repair.
It adds no periodic timer, broker preference, manual mode or business I/O.
It is an additional observer per pool, not a claim of unchanged resource cost;
native power/callback-cost acceptance has not been performed.

## Late receipts and sampling epochs

The pre-existing reset clears RTT, recent delivery samples and chunk metric
flights/rates, without clearing business attempts, route authorization or durable
storage. That retains Android's reset behavior, including its chunk-window reset.

The iOS follow-up also fences late RTT samples: each successful reservation stores
the current opaque metric epoch. A changed network key rotates that epoch; equal
keys are no-ops. Only a matching epoch may train RTT/recent-delivery statistics.
An authenticated receipt for an older attempt still completes the same logical
message and matching hedges, and broker ACK still releases physical capacity.
It is not rejected, replayed, re-encrypted or granted a new business completion.
Returning to an earlier network-key string does not revive an old epoch.

Old chunk metric flights are dropped by reset, so their later bitmaps cannot
train those dropped flights. This is not a new chunk receipt protocol or a claim
to distinguish every cross-interface duplicate after subsequent retransmission.
Sampling epoch fencing is local hardening, not a wire-format addition or a claim
that the referenced Android implementation already used the same epoch fence.

## Verification and remaining boundaries

Eleven synthetic methods are authored: six policy cases for late receipt delivery,
same-key retention, returning network keys, fresh/duplicate receipts, cross-epoch
hedges and dropped chunk metrics; five injected-observer cases for current reset,
old/cancelled/reused observer callbacks, readiness preservation and deterministic
disabled observers. Existing fake-pool fixtures explicitly disable the real OS
observer. Thirty methods in total are authored by this PR; none compiled or run.

The focused JavaScript check compares full retained policy/pool/fixture sources to
the parent increment. It verifies default native observer wiring, owner fences,
reset scope, epoch assignment/receipt gating and unchanged socket/durable/receipt
kernels. Prior diagnostic and lifecycle assertions remain, with declared
normalization only. These checks are not native runtime or network evidence.

NWPath comparison follows [Apple's Network NWPath API](https://developer.apple.com/documentation/network/nwpath),
not SSID polling or the deprecated NetworkExtension NWPath class. Real callback
delivery, same-interface network replacements, suspension/resume, TLS behavior,
power use, throughput/latency, UI/device and full Android parity remain unverified.
There is no promise to distinguish changes not exposed by the OS path observer,
hard-preempt an in-flight receipt, or provide simultaneous network snapshots.
No Swift compilation/XCTest, native/real-network test, CI monitoring or IPA is
performed. No raw reports, private/device evidence or generated packages are
uploaded.
