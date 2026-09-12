# Android Durable Message Hedge Checkpoint

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.

This continues the Desktop checkpoint, not completion of the full multi-broker
specification. The shipping App has not been installed, the running Desktop has
not been replaced, and no PR has been submitted. Full attachment striping,
cross-platform pairing, lifecycle, performance/power acceptance, version bumps,
and coordinated full-runtime deployment remain required.

## Activated Android Code

- `GalaxySSIMqttClient` prepares actual durable small-message publications using
  `MqttPeerRoutes.prepareDelivery` and `MqttDeliveryDispatch`, not just a standalone
  policy simulation. Classification is persisted in the existing encrypted
  outbox row and restored on retry; it is not inferred from user text/ciphertext.
- The existing process-owned pool maintenance tick drives bounded scheduled
  copies. There are no new per-message/per-contact threads or durable ledgers.
  Normal/final messages hedge across currently authenticated common paths;
  typed cancellation/revocation controls race; progress remains single-path.
  The existing 12-slot global limit and two reserved priority slots are shared.
- The same immutable Signal ciphertext/message ID is used on every attempt.
  Each outer envelope uses the existing AEAD with new attempt metadata. The
  encoded packet bound accounts for the metadata, AEAD/padding and MQTT/topic
  overhead. Activation is limited to the configured 65,536-byte small threshold.
  Larger messages still use the current publisher pending durable chunk work.
- Each delayed send rechecks pair binding, expiry, subscribed receive window,
  and physical generation. Pair replacement/revocation invalidates prepared
  authorization. Observations and buffered data have global bounds; the existing
  durable outbox owns retry after the 30-second observation round and restart.
- One logical publication token completes on the first physical PUBACK. That
  does not imply the peer stored the message and does not cancel pending hedges.
  Already-sent copies remain physically accounted until PUBACK/disconnect.
- Both Desktop-agent and phone-contact receive paths validate framed metadata
  only after existing relationship AEAD authentication. Message ID and wire hash
  are validated against decrypted application data inside the existing atomic
  Signal/inbox transaction before ratchet/prekey/inbox state commits.
- Attempt-attributed RX_STORED is emitted only from existing durable inbox proof.
  Duplicate ciphertext uses the same inbox/Signal-identity lane and can repeat
  the stored receipt without creating another task or decrypting again.
- Received RX_STORED must match a local attempt and current authenticated pair.
  Existing ciphertext/key-bound outbox deletion happens before scheduled copies
  are cancelled. UI IDs are taken from the deleted local row, never a peer's
  claimed display IDs. The ACK can arrive on a different current broker.
- Existing authenticated Signal stored-message ACKs also stop pending copies,
  but cannot invent a per-path RTT sample. Receipts do not request receipts.
  Storage exceptions leave transport retry live; this does not eliminate the
  pre-existing crash window between outbox retirement and separate UI updates.

## Verification

- Initial normal main Kotlin compilation passed in **1m 51s**:
  `build/mqtt-android-hedge-main-v1.log`.
- Pure JVM suite passed **172 tests**, zero failures, **5.046 seconds**:
  `build/mqtt-android-hedge-host-v3/tests.log`. This includes 18 actual dispatcher
  cases, seven route-to-dispatch/receipt cases and four traffic cases in addition
  to existing transport tests. Physical Paho clients are deterministic fixtures;
  route host tests use a transparent sealing fixture, not a real TLS network.
- Isolated APK build passed in **3m 27s**, compiling actual app and test Kotlin:
  `build/mqtt-android-hedge-isolated-v1.log`.
- S20U / SM-G9880 / Android 13 / `R5CN319CESA`: **55 tests passed**, zero failures,
  **10.231 seconds**, final `OK (55 tests)` and `INSTRUMENTATION_CODE: -1`:
  `build/mqtt-android-hedge-s20u-device-v2.log`.
- The first device command used the wrong receipt-test class name and reported
  one test-loader failure. It is retained in the `v1` log and is not counted as
  a passing full suite. The corrected complete `v2` run is the evidence above.
- Device classes: atomic inbox (21), route persistence (6), outbox database (10),
  receipt journal (8), wire/AEAD/Android ingress codec (6), hedge policy (4).
  Existing cases overlap prior checkpoints; these are not 55 new product E2E
  tests. The native Signal case now also rejects wrong frame ID/hash, verifies
  ratchet/prekey rollback, then successfully accepts the same valid ciphertext.
- Normal Gradle configuration was restored without the isolated init script.
  Main/test Kotlin compilation and **77 focused tests passed**, zero failures,
  errors or skips, in **3m 20s**: `build/mqtt-android-hedge-normal-test-v1.log`.
  Classes: existing Link protocol (35), dispatcher (18), peer routes (20), and
  traffic policy (4). The latter 42 overlap the pure JVM run; they are not
  counted again as distinct tests. This build excluded native-memory generation
  and full embedded runtime packaging; it is not a shipping APK build.
- Kotlin source-size policy passed (153,600-byte default with the repository's
  existing frozen exceptions), and diff whitespace validation passed.

No public broker was contacted by this checkpoint's tests. No S26U or SM-T575
operation occurred. The verification packages had a plain Application and no
launcher/services/models. Native libsignal was retained; embedded runtime and
other native assets were intentionally excluded. These are **not shipping APKs**.

Only the two packages installed by this test were subsequently uninstalled:
`com.galaxyssi.chat.mqttverification` and `.test`. The pre-existing
`com.galaxyssi.chat.test` remains unchanged. Production `com.galaxyssi.chat`
was absent before and after testing; this run did not uninstall it.

Retained artifacts:

- `build/artifacts/mqtt-android-hedge-s20u/verification-app.apk`
  SHA-256 `DD7C0679E8DF20A3BF941AF3398CF5AE7593CCEFA06F22110CBEFB9219D46232`.
- `build/artifacts/mqtt-android-hedge-s20u/verification-test.apk`
  SHA-256 `6224BCB06CAD1880EDA8B6135676AB04AA3F5D741CA25F0FFD6D6C7DA2AA559B`.

After restoring normal configuration, the matching package/hash-verified
isolated APKs were removed from ordinary Gradle APK output paths, preventing
accidental use as shipping installers. The explicit artifacts above remain.

## Remaining Acceptance

Both endpoints now have the small-message dispatcher in their real publishers,
but actual Android/Desktop native Signal exchange across owned MQTT brokers is
still required. Host fixtures and phone-local crypto/storage tests are not that
acceptance. Do not describe the complete new transport as ready for re-pairing.

The original requirements still include durable chunk bitmap/resume/hash,
coalesced progress, diagnostics, every pairing/return path, ten-window mixed
load, restart/Doze/network chaos, repeated latency/throughput/power measurement,
and complete side-effect recovery. No main UI or Agent processing layout was
changed in this checkpoint.
