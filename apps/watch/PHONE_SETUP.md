# Phone-assisted watch setup (v1)

Implemented here: watch UI, Wi-Fi-only receiver, NSD announcement, interactive numeric comparison, cloud-profile import, and forwarding fresh desktop pairing offers through the existing Signal/MQTT pairing flow. **The Android phone developer-options UI and its NSD/client integration are not part of this change.** `tools/phone_setup_client.py` is the interoperability reference client.

## User flow

A watch without any cloud profile or paired desktop opens the setup Activity. Connect the phone and watch to the same Wi-Fi, then use GalaxySSI on the phone → Settings → General → Developer options → Configure watch (phone UI still to implement). Existing configured watches keep their chat home and can open the receiver explicitly from Settings → Configure from phone.

The main page has the horizontal logo/wordmark, clock, two steps, and connection status. Connection help shows the watch IPv4 address and dynamically allocated port. Subpages omit the clock. Comparison appears only after a handshake, with a fresh six-digit code and explicit accept/cancel buttons. A cloud profile is acknowledged only after encrypted storage succeeds; the watch then returns to chat. A desktop offer returns `pairing_started`, not `saved`: the existing desktop authorization must finish before use.

The service binds a Wi-Fi interface, never a wildcard/cellular address. It advertises `_galaxyssi-watch._tcp.` with TXT `v=1`. NSD failure still permits manual connection. It closes on Activity pause, Wi-Fi/address changes, successful delivery, three failed sessions, or a five-minute window expiry. Open the page/retry to restart. There is no ADB, Bluetooth, background listener, or automatic trust based on LAN membership.

## Wire format

TLS 1.2/1.3, self-signed AndroidKeyStore server certificate. Each frame is a 4-byte unsigned big-endian UTF-8 length followed by a JSON object; 2–32768 bytes. Normal socket deadline 60 seconds. No HTTP endpoints or web browser support.

1. Client generates random 32-byte Nc and sends `{type:"hello",version:1,commitment:hex(SHA256(Nc))}`.
2. Server generates random 32-byte Ns, sends `{type:"challenge",version:1,commitment:hex(SHA256(Ns))}`.
3. Client reveals `{type:"reveal",nonce:hex(Nc)}`; server verifies its commitment and reveals `{type:"reveal",nonce:hex(Ns)}`. Client MUST verify this commitment.
4. Both display the zero-padded six-digit decimal reduction modulo 1,000,000 of `SHA256(UTF8("GalaxySSI-Watch-Setup-v1") || SHA256(serverCertificateDER) || Nc || Ns)`, interpreted as an unsigned big-endian integer. Commitments precede reveals; changing the TLS identity changes the comparison code.
5. User explicitly compares and accepts on BOTH devices. Client sends `{type:"confirm",accept:true}`. The server also requires its own on-watch approval, then sends `{type:"ready"}`. Nothing confidential may be sent before this point.
6. Client sends configuration; server validates, applies, sends a result and closes.

Trust is confirmed per session; there is no persistent phone binding or unattended resynchronization in v1. Do not trust a self-signed certificate without the complete commitment exchange and human comparison. The reference client's bootstrap trust policy must never be reused for unrelated API/desktop requests. This bespoke provisioning protocol needs independent security review before unattended or large-scale distribution.

Cloud payload:

```json
{"type":"configure","kind":"cloud","profile":{"endpoint":"https://api.deepseek.com/chat/completions","model":"YOUR_MODEL","api_key":"YOUR_KEY","api_style":"openai"}}
```

Supported API styles reuse watch validation: `openai`, `anthropic`, `gemini`. Endpoint must be HTTPS with the matching provider request path. Provider/model catalogs stay on the phone; v1 imports one selected profile. Existing thought-mode behavior stays disabled by the watch's existing API request policy. Result: `{"status":"saved","kind":"cloud"}`. This confirms storage, not reachability or validity of the provider key.

Desktop payload: `{"type":"configure","kind":"desktop","pairing_offer":{...fresh desktop QR contents...},"agent_id":"optional selected agent"}`. The phone passes the fresh pairing offer, never its own Signal identity/session secrets. Result `{"status":"pairing_started","kind":"desktop"}` means the request was submitted, not that the desktop authorized it. The watch waits for its own desktop pairing and agent listing. In v1 use the current watch UI to finish selection if needed; automatic receipt of phone configuration is not a cloud account sync.

## Developer check

Open receiver from watch settings. Run `python tools/phone_setup_client.py WATCH_IP PORT` to compare codes without changing settings, or add `--config PRIVATE_JSON_FILE` to import after manual confirmation. Never include keys on the command line or commit the private JSON file. No payloads are logged.

Instrumentation tests exercise TLS/commitment roundtrip and acknowledgment with an in-memory handler (no user credential changes), commitment mismatch rejection, and local refusal. Test via `com.galaxyssi.watch.WatchPhoneSetupTest`.
