# Owned MQTT Lab

This test-only harness runs three independent loopback TLS brokers using pinned
[aMQTT 0.12.0](https://pypi.org/project/amqtt/0.12.0/). The public
[broker configuration reference](https://amqtt.readthedocs.io/en/v0.11.2/references/broker_config/)
is background documentation; this harness was checked against the installed
0.12.0 API. It uses an existing MQTT implementation, not a partial mock server.

Create a Python 3.11 virtual environment **outside the source tree**, install
`requirements.txt` there, and run `smoke.py` using that interpreter from the
repository root. No production Desktop or App needs to be stopped.

Example for this development machine:

```powershell
& C:/Users/agent/MQTTDiagnostics/20260913-owned-lab/runtime/Scripts/python.exe tools/testing/mqtt_owned_lab/smoke.py
```

## Safety

- Listeners bind only `127.0.0.1` with OS-assigned ports, never a LAN interface.
  There is no host argument or path to send these tests to public brokers.
- An ephemeral one-day CA signs a localhost/IP server certificate. Clients
  explicitly trust that CA and still require chain and hostname verification.
  No CA is installed in Windows or Android, and no TLS validation is disabled.
- Anonymous MQTT authentication is test-only and loopback-only. Production
  paired identity, topic and payload state is never read. Test secrets, TLS
  files and the isolated route database use a disposable temporary directory.
- The Desktop client factory maps the three known catalog endpoints to these
  listeners. It does not edit the catalog, production configuration or DNS.
- Cleanup disconnects all test client workers and shuts down the brokers.
  The harness is a bounded run, not a background service.
- IDs `emqx`, `hivemq`, `mosquitto` are labels. These local aMQTT listeners do
  **not** emulate provider-specific packet limits, quotas or availability.

## Smoke Coverage

The test runs the real Desktop `BrokerPool`, `MqttPoolClient`, `PeerRoutes`,
Paho TCP/TLS callbacks, pair AEAD and SQLite route persistence. Two directed
mailboxes complete authenticated resume over three paths. Synthetic messages
exercise each path in both directions; explicit per-path checks use scheduler
attempt metadata, while the outage checks let the policy choose a path.

It rejects unknown-CA and wrong-hostname certificates, stops one broker, checks
automatic communication on the two remaining paths, restarts the broker, and
checks resubscription/authenticated recovery and bidirectional delivery again.
There is no forwarding between the three broker instances.

This is **not** native Signal ratchet acceptance, durable business-message
receipt testing, real model execution, UI/attachment acceptance, a performance
benchmark, an App/App test, or a power test. Reported ten-message receive times
are high-resolution local smoke observations, not internet p50/p95 evidence.

The first smoke attempt incorrectly restricted authorization to one path without
letting the scheduler select that path. The fixture now marks the other paths as
already attempted for those explicit path checks; production policy was not
relaxed. The first successful run used a low-resolution Windows monotonic clock
for sample timing; subsequent runs use `perf_counter` for the report only.

## Native Business Smoke

`native_smoke.py` adds two separate endpoint processes with independent real JVM
Signal identities, encrypted SQLite state and production Desktop peer-message
handling. It uses the same loopback-only physical client adapter as `smoke.py`.
The controlling interpreter needs the lab requirements; the endpoint interpreter
needs the complete Desktop backend requirements and a built worktree sidecar.
Configure `JAVA_HOME` before running, for example:

```powershell
& C:/Users/agent/MQTTDiagnostics/20260913-owned-lab/runtime/Scripts/python.exe tools/testing/mqtt_owned_lab/native_smoke.py --endpoint-python C:/Users/agent/MQTTDiagnostics/20260913-desktop-runtime/Scripts/python.exe --report-dir build/mqtt-owned-native
```

Both endpoints use production `encrypt_signal_payload`, `on_mqtt_message`, the
bounded ingress workers, Signal receive handoff, dispatch guards, durable outbox
and `PeerChatStore`. The real peer-message handler is not mocked. No provider,
model, proactive worker, real user pairing registry or installed App is used.
Trusted bundle exchange is supplied by the isolated control process; the QR
pairing ceremony is not part of this test.

Cases cover native pre-key/ratchet exchange, three copies observed over three
actual TLS paths with one business dispatch, a fragmented native envelope, one
broker down, loss of all sender ingress (including application receipts), both
endpoint process trees killed and restored using the same databases, all three
brokers down, durable queue recovery through one restored broker, and restoration
of the full path set. Windows-only abrupt-process testing kills only child PIDs
owned by the harness. All test workers, JVMs and brokers are stopped afterward.

Loss is injected at the sender's physical receive callback after MQTT/TLS, not
by forging a PUBACK or a durable application receipt. Fragmentation uses ignored
synthetic padding within the unchanged application envelope limit; it is **not**
an image/file/video artifact test. Snapshot checks read actual stored message
hashes, immutable IDs and dispatch-attempt counts, and wait for the bounded
ingress queue to drain before asserting duplicate handling.

The two endpoint processes assemble the normal bridge's pool/ingress/publisher
components while running only route maintenance and durable queue replay. The
complete production startup/recovery supervisor, UI click-to-send, real model
tasks, Android/JNI and phone lifecycle still require separate acceptance.
In particular, lower-level offline queue success cannot prove that the Desktop
UI send entry point allows offline enqueueing.

Times in the report include controller RPC and SQLite snapshot polling; do not
use them as transport RTT, unbiased latency distributions or performance gates.
Any captured native ingress error fails the suite, even if all user-visible
messages eventually arrive. Test logs are retained in the report directory;
ephemeral credentials and private Signal databases are deleted with the lab.

Add `--delay-resume` to hold actual incoming MQTT callbacks while one broker is
stopped and restarted. The bounded buffer releases the old authenticated resume
ACKs only after a newer local epoch exists. The test verifies that the queue
drains without ingress errors and fresh authentication still permits delivery.
It does not fabricate an ACK, change production timing or disable validation.
Error observations survive test endpoint restarts, so a later clean process
cannot hide an earlier failure. See the
[native checkpoint](../../../docs/testing/MQTT_NATIVE_BUSINESS_20260913.md).

Add `--offline-peer-entry` to exercise the actual Desktop direct-contact,
Agent push and mobile diagnostic APIs with all brokers stopped. All three
entries must durably accept the message, without claiming phone delivery.
The endpoint process is then killed and restarted using its existing data;
message IDs, queued peer card and immutable native ciphertext must survive.
The notification APIs start the normal shared retry owner, which the endpoint
explicitly stops and joins during cleanup. This final scenario does not feed
Desktop-to-phone envelopes to another Desktop or claim an Android receipt.
See [notification queue checkpoint](../../../docs/testing/MQTT_NOTIFICATION_QUEUE_20260913.md).

Add `--path-cycles 30` for repeated owned-listener loss/recovery. The failed
listener rotates across the three catalog IDs; each cycle sends in both
directions while that listener is down and again after its restoration. This
adds 90 business messages to the basic nine-message suite. The option is bounded
to 0-100 cycles and never uses public brokers. These controller-polled timings
are not a performance comparison or an unbiased latency percentile.

Add `--defer-after-selection` to withdraw the endpoint's real MQTT subscriptions
after the outbox selects a message but before wire preparation. The message must
remain queued without a nonexistent broker token or a consumed send attempt.
Restoring subscriptions must resume the original ciphertext/identity into one
real business row. TLS, native Signal and receipt validation remain unchanged.
This adds one business message. See
[deferred selection checkpoint](../../../docs/testing/MQTT_DEFERRED_SELECTION_20260913.md).

Failure diagnostics retain each inbox entry's payload type, pending broker token
IDs and both endpoints' last snapshots. Receipts must not be mistaken for missing
chat rows simply by comparing inbox and history counts. Per-message completion
markers are printed during long runs; the final JSON report remains the verdict.
