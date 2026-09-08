# GalaxySSI Link Sidecar

Local JVM service that owns Desktop Signal Protocol session state and identity signing.

It uses the official `org.signal:libsignal-client` package. Python calls this service over
`127.0.0.1` and MQTT only carries encrypted Signal envelopes.

Endpoints:

- `GET /health`
- `GET /bundle`
- `POST /decrypt`
- `POST /encrypt`
- `POST /replace-peer`
- `POST /remove-peer`
- `POST /sign`
- `POST /verify`

The signing endpoints accept only bounded application payloads over loopback. The private
identity key never leaves the sidecar.

Session mutations are serialized per peer name inside the sidecar. The bounded
256-stripe lock set covers encrypt, decrypt, peer replacement, and peer removal;
it does not retain a growing lock map for every encountered identity. HTTP body
reading and response writing stay outside the session lock. Individual store
method locks alone do not protect a complete ratchet read/modify/write operation.

Run `verifySignalConcurrency` with Gradle to exercise 10 threads and 1,000
bidirectional libsignal round trips using disposable in-memory identities. This
probe does not access the production identity store or replace device pairing.
