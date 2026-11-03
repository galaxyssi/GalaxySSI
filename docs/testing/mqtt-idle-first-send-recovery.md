# MQTT idle and first-send recovery

## Failure modes

- An existing Android pool treated repeated start/network-available calls as no-ops,
  even when a physical socket had silently stopped working.
- A missing connection callback or SUBACK could leave a path in its old generation
  indefinitely. The Desktop loopback watchdog only refreshed subscriptions.
- Renewing a local advertisement invalidated the entire relationship until the new
  ACK arrived, including surviving, already authenticated paths.
- The Agent connector treated both local queue acceptance and physical publication
  as `mqtt_published` in dedicated history.

## Recovery contract

Android checks path health on an independent maintenance executor every two seconds.
Connection establishment and subscription confirmation each have a 20-second
watchdog. A first-send/start/network-available signal also checks the pool immediately;
repeated demand is coalesced and rate-limited per path. Offline paths retain retry
backoff and no network connection is started while the network is unavailable.

Desktop repairs the exact broker/generation associated with a stalled probe. Retiring
a path rejects late callbacks and closes only that socket, then lets its existing
worker reconnect. Subscription calls execute outside the path state lock.

A resume renewal retains the previous authenticated lease only for physical
generations that are still live, subscribed and unexpired. The remote authenticated
route policy must also admit the path. New generations still require a new ACK;
identity replacement, topic replacement, revocation and expiry block reuse. Path
authorization is applied before ranking, including for large messages and receipts.

`QUEUED` remains accepted durable work, not evidence of remote receipt. Connector
dispatch now records `mqtt_queued` and queued history status instead of claiming
publication. This does not change the task/turn IDs, deduplication or receipt rules.

## Regression coverage

- Silent idle disconnect followed by a single send/start signal.
- Repeated network-available callbacks without a network-flag transition.
- Stalled CONNECT and SUBACK with other brokers still healthy.
- Late callbacks and stale watchdog generations.
- Healthy repeated demand without reconnect/subscription churn.
- Subscription callbacks completing while Paho is publishing a subscription.
- Lease renewal and one flapping broker without revoking surviving paths.
- Lease expiry, stale ACKs, identity/topic replacement and revoked relationships.
- Large-message selection restricted to authorized paths before ranking.
- Existing MQTT delivery, receipts, chunks, pairing, recovery and isolation suites.

Run Android tests with `:app:testDebugUnitTest --tests 'com.galaxyssi.chat.Mqtt*'
--tests 'com.galaxyssi.chat.AgentConnectorDispatchBindingTest'` and assemble the APK.
Run Desktop `test_mqtt*.py` through `tools/dev/test-run-kernel.py`, which isolates
test databases/configuration from the user's running Desktop data.

## Device acceptance

Cover-install on the already paired phone without clearing data or re-pairing.
Send one uniquely identified request after idle, verify its source/turn IDs at
Desktop ingress, then verify the returned result on the same phone conversation.
Repeat after background/foreground and network loss/recovery. Check that another
broker's reconnection does not reset the healthy path and that no task is executed
twice. Do not equate `/health` HTTP success or a broker PUBACK with peer delivery.

Public broker reachability is independent of these recovery rules. If all configured
paths are unreachable, messages remain in the durable queue; this patch does not
disable certificate verification or introduce an unencrypted fallback.
