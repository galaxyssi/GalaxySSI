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
