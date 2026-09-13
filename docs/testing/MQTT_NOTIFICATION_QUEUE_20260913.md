# Durable Notification Acceptance

Date: 2026-09-13. Original checkpoint source: Desktop 1.1.52, not then deployed.
Installed/running versions remain App 1.1.114 (1000) / Desktop 1.1.51.
This is a development checkpoint, not complete multi-broker acceptance.

Later deployment update: the user requested coordinated v1.2.0 versions and
installation/startup. Desktop 1.2.0 now runs from the full Python/Signal JVM
package; these notification changes are included. The UI version and three
TLS/subscription paths were inspected. This does not substitute for the
remaining notification, phone artifact or outage acceptance tests below.

## Changes

- Agent push and mobile diagnostics no longer reject an authorized target
  just because the MQTT pool is absent or all paths are offline. Each target
  receives an immutable message ID and native Signal ciphertext in the existing
  durable outbox before the API reports acceptance. No synchronous network
  flush is required on these API paths.
- Responses use `agent_push_queued` / `mobile_test_queued`, `queued=true`,
  `delivered=false`, per-target IDs/states, and accepted/failed counts. Partial
  broadcast enqueue is explicit; an unselected multi-peer send is rejected.
  Pre-commit failures never count as accepted. Repeated HTTP calls are new
  logical sends, not client-token-idempotent retries.
- Queue telemetry or retry-worker startup failures cannot invalidate a prior
  durable commit. Concurrent callers share one guarded retry worker. Normal
  bridge startup also owns retry recovery. Existing authenticated receipts,
  pair checks, task identity, priorities and encryption remain unchanged.
- Proactive delivery no longer treats any nonempty result dictionary as
  successful delivery. Its snapshot reports acceptance, not a live peer receipt.
- Connector self-test reports `queued` / `waiting_delivery` and a separate
  queued summary. Neither API success nor a Broker ACK proves phone receipt.
  Existing diagnostic presentation now includes the pending state; no chat
  layout, background or input controls changed.
- Replaceable connector status and pre-revocation best-effort messages keep
  their distinct semantics; they were not blindly moved into a durable queue.

## Verification

| Scope | Result | Evidence |
| --- | --- | --- |
| Notification/proactive/diagnostic focused tests | 21 passed, 0.763s | `build/mqtt-notifications-diagnostics-v1.log` |
| Latest delivery/lifecycle/pairing/recovery regression | 207 passed, 9.944s | `build/mqtt-notifications-regression-v3.log` |
| Earlier overlapping broader selection | 217 passed, 25.019s | `build/mqtt-notifications-regression-v2.log` |
| Desktop renderer and structure, version 1.1.52 | 37 passed, structure OK | `build/mqtt-notifications-ui-v3.log` |
| Push API authorization, encrypted wire and local CLI | Passed | `build/mqtt-notifications-api-smoke-v2.log` |
| Owned native Signal/TLS business and process recovery | Nine business messages plus offline API scenarios passed; both endpoint error logs empty | `build/mqtt-owned-notifications-v1/report.json` |

Counts overlap and are not a sum of distinct end-to-end cases. Unit/API smoke
tests use isolated state and fixture Signal encryption. The owned native run
uses actual JVM Signal, unchanged production outbox/ingress and real loopback
TLS brokers. The extra Agent/diagnostic scenario proves two queued ciphertexts
survive abrupt process death, not that a phone consumed them.

An initial broad run exposed three outdated publisher test fixtures lacking the
already-existing `transport_traffic` argument. Fixtures now explicitly assert
the supplied classification; fairness, terminal-reserved capacity and lock
release checks remain. The API fixture now supplies structurally valid Signal
fields, and its fake physical publication is explicitly flushed after enqueue.
Production validation was not relaxed. All smoke data/config/token paths are
isolated from the running Desktop.

## Remaining Work

The new notification implementation is not in the currently running 1.1.51
Desktop. Real S20U pairing and one background Codex round-trip have now passed
against the installed pair; see [phone checkpoint](MQTT_S20U_BACKGROUND_20260913.md).
That test also exposed delayed Android final-response consumption while paused.
It does not validate this new notification API, all peers, App/App, artifacts,
ten windows, the full outage matrix, performance distributions or power.
The full development objective and PR remain open.
