# Phone-assisted watch setup

Entry: Android Settings → General → Developer options → Configure watch.

The phone implements Wi-Fi NSD discovery and manual IPv4/port entry, certificate-bound six-digit comparison, cloud provider/model selection using the existing Android catalog, copying saved model credentials without modifying phone contacts, optional HTTPS connection testing, transfer confirmation, QR/manual desktop offers, authorization polling, agent selection, and recovery after disconnection. Both sides must approve the comparison before any credentials are sent. Cloud test results describe the phone connection only.

Drafts stay in the Activity memory, not saved-instance state or plaintext preferences. Leaving the app closes the setup connection except during its QR scanner step. Reconnection requires another comparison; drafts may be lost if Android destroys the process. Release builds protect the screen against capture. Never log payloads or keys.

The watch listens only on a Wi-Fi IPv4 interface and advertises `_galaxyssi-watch._tcp.`. Setup is foreground-only, closes on pause/address changes/completion, and expires after 15 minutes. Screen stays awake within this bounded setup session. Each receiver allows three failed sessions. After confirmation the idle read deadline is five minutes; ordinary phone requests have a 30-second reply deadline.

## Wire protocol

TLS 1.2/1.3 with an AndroidKeyStore EC certificate. Frames are a four-byte big-endian length followed by UTF-8 JSON (2–32768 bytes).

1. Client commits SHA256(random 32-byte Nc) in `{type:hello,version:1,commitment:hex}`.
2. Watch commits SHA256(random 32-byte Ns) in `{type:challenge,version:1,commitment:hex}`.
3. Both reveal their nonces and validate commitments.
4. Compare the six-digit decimal SHA256(`GalaxySSI-Watch-Setup-v1` || SHA256(certificate DER) || Nc || Ns), modulo 1,000,000. Each device requires explicit human approval.
5. Client sends `{type:confirm,accept:true}` and waits for `{type:ready}` before sending configuration.
6. Every request has `type:configure` and one of the kinds below.

- `cloud`: profile contains `endpoint`, `model`, `api_key`, `api_style` (`openai`, `anthropic`, `gemini`). Watch validates and encrypts storage; `status:saved` acknowledges storage, not provider validity. The channel closes.
- `desktop`: `pairing_offer` contains fresh computer pairing QR contents, not the phone's Signal identity or sessions. `status:pairing_started` means submitted, not authorized. The channel remains open.
- `desktop_status`: within the same authenticated session, returns `pairing_started` or `agents_ready` with an `agents` array of `{id,name}` from the paired watch connection.
- `select_agent`: `agent_id` must belong to that authorized desktop's current list. Watch saves the selected route; `status:saved,kind:desktop,agent_name:...` confirms completion and closes the channel.

There is no persistent phone trust or unattended resynchronization. The bootstrap TLS trust manager must never be reused outside this numeric-comparison protocol. Independent protocol review is still required before large-scale distribution.

`tools/phone_setup_client.py` remains a diagnostic handshake/cloud-transfer client; the Android UI implements the complete desktop flow. Tests use in-memory handlers and dummy credentials, not user API keys.