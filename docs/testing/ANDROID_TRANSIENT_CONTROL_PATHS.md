# Android transient control paths

Caller-retried Desktop queries already bypass the durable outbox. Their encrypted
wire previously fell through ordinary-message classification, losing priority and
using only one immediate path. The Desktop-control entry point now explicitly
passes its existing transient-query classification to the wire sender.

Small query packets receive a descriptor bound to the current relationship secret,
authenticated route and broker generations. Each authorized immediate path may
publish the same sealed bytes. Capacity is shared, not multiplied by broker count.
Every physical copy revalidates the relationship before sending; revocation or a
changed path never grants access to a replacement route. Large replies fall back
to ordinary single-path admission. Durable messages and fragments are unchanged.

The result is one admitted physical token, not proof that the peer received or
processed the request. Extra copies do not register phantom completion events with
the business receipt watchdog. No new outbox or retry owner is introduced.

The existing guarded publisher is extracted unchanged into MqttGuardedPublish.kt
to keep GalaxySSIMqttClient.kt below the repository source-size limit. No UI or
model selection changes are included.

Regression coverage exercises exact-byte copies, token registration, wrong secret,
unconfirmed/expired/revoked relationships, changed paths, capacity reserve and
large-result fallback with the real routing and pool classes.

The live S20U probe remains incomplete: two queries returned before the existing
deadline, while the third was accepted late. Desktop did receive and admit the
third response; this run does not establish stable latency or identify a public
broker as the root cause. No model tasks were created or repeated, and no timeout
was extended to change the original failed verdict.
