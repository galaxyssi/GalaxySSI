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
