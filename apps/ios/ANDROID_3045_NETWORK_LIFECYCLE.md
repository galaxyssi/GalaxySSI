# Android #3045: offline MQTT lifecycle follow-up

Reference: Android #3045, merge `d31829d8d047abb457cc3b67c5ea68eeb729b94f`,
especially `MqttBrokerPool.networkUnavailable`, `networkAvailable` and `connect`.
The earlier iOS runtime/result follow-ups #4120/#4122/#4123/#4124 are already
merged. This is a missing lifecycle correction, not a replacement of those PRs
or a claim that the complete #3045 acceptance matrix is finished.

## Actual gap and correction

The iOS monitor previously acted only on recovery. An unavailable observation
did not withdraw an apparently ready socket's subscriptions; timer-driven start
and scheduled reconnect also ignored known offline state. The pool could keep
advertising a path until a socket error, subscription timeout or keepalive caught
up, while reconnect timers continued attempting TLS connections offline.

Each client now retains one queue-confined network-availability state. Unknown
permits the initial attempt while awaiting the first monitor callback. The first
offline observation or a subsequent transition offline cancels scheduled reconnect,
detaches/cancels the current socket and uses the existing failure path to clear
subscriptions, cancel watchdogs, reset physical attempts and emit a disconnected
snapshot. Without a socket it still withdraws readiness. Repeated identical
observations do not repeat that work. Network recovery wakes the existing demand
check once; CONNECT/CONNACK, fresh connection generation and exact SUBACK readiness
are still required. A satisfied network is not peer delivery or broker readiness.

Direct start, scheduled reconnect, demand wake and live-transport admission all
check the same gate. A timer already dequeued during withdrawal cannot open a new
socket because start repeats the gate. Explicit stop still overrides recovery,
resets monitor state and fences callbacks by monitor identity. Stale socket
callbacks remain fenced by NWConnection identity; the broker pool still checks
configuration, generation, connection and topic membership.

No journal, Signal session, durable inbox/outbox/chunk record or business delivery
completion is erased. Path-gated physical attempts fail through the existing reset
path; ordinary legacy queue retention and replay remain unchanged. No message is
newly reported delivered because of a network callback. Android's version bump,
broker preferences and manually selected transport modes are not copied.

## Verification boundary

Ten synthetic XCTest methods are authored in the already registered broker-pool
test source: unknown/initial-offline states, duplicate events, repeated recovery,
monitor reset, independent paths, withdrawal/publication rejection, fresh
generation/full subscription readiness, stale ingress and unaffected other paths.
These exercise the shared state and fake broker pool, not NWPathMonitor or real
sockets. They have not been compiled or executed.

The focused JavaScript guard validates production wiring and exact retained
surrounding code against main `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.
Source checks do not prove native timing, radio behavior, callback order, actual
TLS cancellation, power use, UI, device or process-death acceptance. No Swift
compile/XCTest, native tests, network probes, CI monitoring or IPA is requested
here. No raw reports, private/device evidence or generated packages are committed.

The full Android #3045 includes lifecycle diagnostics, mixed-workload latency,
background projection, interrupted result commit and wider release acceptance.
Existing implementations must still be assessed against those requirements; this
follow-up does not mark them all complete or introduce a background execution
entitlement that iOS does not grant.
