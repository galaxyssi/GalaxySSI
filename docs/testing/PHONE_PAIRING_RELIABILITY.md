# Phone Pairing Reliability

## Delivery contract

Phone QR claims, bundle confirmations, explicit recovery requests, and friend
decisions are persisted in encrypted preferences before publication. A broker
ACK is not a peer confirmation. An authenticated relationship receipt must bind
the remote identity, original control ID, and canonical SHA-256 payload digest.
Receipts never request receipts.

Controls retain the same ID across retries and process restarts. The queue holds
at most 64 entries, coalesces equivalent pending controls, sends at most four due
controls per drain, uses exponential backoff capped at 30 seconds, and permits at
most 20 attempts within the existing ten-minute pairing-control validity window.
It does not publish continuously while disconnected. Current rotating
relationship topics are resolved on each retry; one-time QR rendezvous topics
remain fixed for that particular claim.

Successfully processed duplicate controls receive another receipt without
reapplying their effects. Failed imports are not recorded as successfully
processed. Ordinary bundle/approval delivery does not replace an established
Signal session; only explicit session recovery may do so. Startup no longer
replays approvals for every healthy contact.

Desktop QR claims also survive an Android process restart. Restoration requires
the same local identity and an unpaired Desktop link. Confirmation, rejection,
or timeout retires the pending claim. QR expiry and one-device token binding
remain unchanged; no security check is weakened.

## Automated coverage

- Dropped initial control and recreated delivery ledger.
- Lost receipt and bounded retries with unchanged control ID.
- Broker submission does not retire a control.
- Wrong peer, wrong fingerprint, wrong ID, and wrong payload hash.
- 1,000 duplicate approvals coalesce to one pending record.
- Rejection supersedes pending approval.
- Global queue capacity, expiry, and four-control drain limit.
- Ordinary bundle versus explicit recovery and canonical nested JSON hashing.
- Android encrypted persistence in a dedicated synthetic namespace.

The device test does not send MQTT traffic, add/delete contacts, modify real
Signal sessions, clear user data, or execute tools.

## Real-device acceptance still required

Install the updated Android build on both phones. From a fresh pairing, scan in
one direction only, approve once, and verify messages and receipts in both
directions without a second scan. Repeat with a lost first confirmation,
temporary disconnection, and process restart. Verify pending confirmations
settle to zero and that established conversations remain unchanged.

For Desktop, use a newly generated QR rather than an expired or already-bound
offer. Verify the new client registers, Android receives confirmation and the
Agent list, and both directions work. Repeat with Android process death during
the handshake. Do not treat a healthy broker connection as proof of pairing.

Single-phone synthetic tests cannot certify two-phone pairing or S24+ Desktop
registration. Record those results separately from unit-test passes.
