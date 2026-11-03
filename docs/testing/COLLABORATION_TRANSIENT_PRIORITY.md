# Transient collaboration control traffic

Small caller-retried collaboration queries and stored-message receipts retain
their traffic classification after Signal and outer-wire encryption. Previously
the opaque packet classifier treated them as ordinary messages, even though the
sender intentionally does not create a durable outbox entry for these exchanges.
Ordinary backlog could therefore consume their available physical send slots.

The fix uses the existing bounded control/receipt reserve. It does not increase
timeouts, packet limits, queue sizes, or retry counts, and does not create a second
outbox. A paired-route descriptor verifies the original fingerprints and shared
secret, checks authenticated readiness, and rechecks revocation/route generation
immediately before publication. Payloads exceeding the existing small-packet
threshold retain ordinary priority; fragmented evidence keeps its existing path.
Caller deadlines and response identity validation remain unchanged.

## Automated coverage

`test_mqtt_transient_priority.py` uses the actual pool policy, paired resume
exchange, outer-wire encryption and registered-client publication entrypoint.
Physical brokers and the Signal cipher are fixtures. It verifies:

- Query and receipt admission while ordinary physical slots are full.
- The unchanged global capacity bound when the reserve is also full.
- Large evidence pages cannot claim the small control reserve.
- Wrong pairs, unconfirmed epochs, revocation races and reconnect generations.
- No second durable outbox and no modification of encrypted reply content.

`test_mqtt_query_delivery.py` checks the explicit message-type classification.
These tests are not a phone/broker end-to-end result or proof of team advantage.
Real phone evidence reads and peer artifact handoff require separate acceptance.

## Diagnosis boundary

Publication logs include the existing content-free admission reason alongside
the return code. Broker connectivity, verified peer readiness, local admission,
and end-to-end result receipt are distinct observations. This classification fix
does not by itself prove that historical receive-queue latency is eliminated.
