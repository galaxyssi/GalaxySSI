# Android #3045: observed MQTT path diagnostics

Reference: Android #3045, merge `d31829d8d047abb457cc3b67c5ea68eeb729b94f`,
`MainActivityMqttDiagnostics.kt` and `MqttBrokerPool.snapshot`.
This extends the same iOS PR as the offline lifecycle correction, initially
`13917b93c`, rather than creating a duplicate PR for #3045.

## Actual producer and owner

Each production client returns its diagnostic snapshot on its existing serial
queue, without opening a connection, waking recovery, publishing or changing
subscriptions. State distinguishes disconnected, connecting, subscribing,
receive-subscriptions-ready, recovering and unavailable network. Explicit stop
takes precedence over unavailable network. Readiness requires a nonempty desired
topic set and all active subscription acknowledgements. It is not peer delivery.
Unknown/unobserved remains a separate presentation state, not invented readiness.

Counters report actual distinct desired/active/pending topics, queued and in-flight
physical publish packets, and reconnect starts. The reconnect count uses a
saturating lifetime connection-start counter, not the backoff index that resets
on CONNACK. Initial connection is not a reconnect. These are physical transport
observations, not counts of durable business messages or application completions.

The connection pool reads all three configured clients and rejects wrong broker
or configuration labels. A second queue-confined owner check discards the entire
read if the pool stopped or reconfigured during collection. Cancellation is
checked in the calling Task before reads and after the final queue return, not
incorrectly inferred inside an ordinary DispatchQueue closure.

The runtime checks its lifecycle before/after the await. MessageCoordinator reads
only its current journal runtime and verifies that owner again after suspension;
legacy mode reads only its actual single client with no invented multipath
delivery statistics. A blocked/missing owner returns no observed paths. No global
cross-profile snapshot cache or new persisted diagnostic data is introduced.

Verified delivery summaries come from the existing scheduling policy. Only
authenticated committed peer receipt handling contributes samples there; PUBACKs
are not promoted to delivery. Existing 32-sample retention, five-minute freshness,
small-sample p95 suppression and peer/network reset API semantics are unchanged.
This does not claim that every existing policy reset API is already wired to all
OS radio/interface transitions; that wider integration still needs assessment.

## Existing diagnostics page

The existing Link Diagnostics list now includes EMQX, HiveMQ and Mosquitto in
catalog order, observed phase, reconnect/physical packet counts, subscription
counts and peer-confirmed delivery summaries. Missing paths show not observed;
missing delivery samples remain absent. p95 needs at least 30 samples and a value.
Status text and format strings use the existing English-fallback/Chinese-resource
localization path. No private topics, contacts, packet bodies, routing IDs,
configuration IDs or error text are displayed or logged.

Refresh is serial once per second only while this view's scene is active. SwiftUI
task cancellation prevents applying a late result after disappearance or scene
change. This is sampled observational state, not a simultaneous all-socket
snapshot, a zero-staleness guarantee or hard cancellation of a busy client queue.
The existing anomaly clear action retains its scope; it does not reset RTT or
change scheduling. No new control, broker preference or manual switch is added.

## Verification boundaries

Nine additional synthetic XCTest methods cover state precedence, a never-started
native client, a stopped pool, exact fake-path counters with no publication or
readiness side effects, unobserved paths, wrong broker/configuration, reconfigure
and stop during read, and cancellation. They are added to the already registered
broker-pool source. Together with the ten lifecycle additions, nineteen methods
are authored by this PR; none compiled or executed. The native-client fixture
does not call connect or exercise an actual socket/monitor.

The source guard compares full retained client, path, pool, runtime, view and
existing fixtures against the initial lifecycle commit. The coordinator retains
new main `26259d650` including #4593/#4594/#4595 acceptance and observation work,
merged without changing those kernels. Older lifecycle and active-observation
guards normalize only the declared observational additions; probe-owner checks
keep the newer main chain through those guards. Their original assertions remain.
Scheduling, Signal/journal/inbox/outbox,
chunking, route/receipt and delivery kernels are unchanged.

No Swift compilation, XCTest/native tests, screenshots/UI rendering, real broker,
device, background execution, power, latency benchmark, CI monitoring or IPA is
performed. Source checks and authored fixtures are not native acceptance. No raw
reports, private evidence or generated artifacts are committed. This is not full
#3045 or overall Android parity; mixed-workload and interrupted-run acceptance,
background OS constraints and wider runtime behavior remain separate work.
