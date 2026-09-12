# Desktop Durable Message Hedge Checkpoint

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.

This is a development checkpoint, not completion of the full multi-broker
specification. No shipping Android APK was installed and the running Desktop
was not replaced. Android's actual attempt dispatcher, attachment striping,
cross-platform pairing, lifecycle, performance/power acceptance, version bumps,
and PR remain outstanding.

## Activated Code

The existing Desktop durable outbox publisher now prepares small immutable
Signal messages through `PeerRoutes.prepare_delivery` and `DeliveryDispatch`.
The final encoded packet bound includes attempt metadata, existing outer AEAD,
Base64 and MQTT/topic overhead. The current activation threshold is 65,536
bytes. Larger messages continue through the existing single-packet/fragment
publisher until the durable chunk stage is integrated.

- Business message ID and Signal-wire hash come from the existing outbox row.
  `transport_traffic` is persisted with that row, not guessed from ciphertext.
- Normal/final small messages use an initial path and delayed alternate copies.
  Typed cancel/revocation controls race currently healthy common paths. Progress
  remains single-path. All physical sends share the existing 12-slot policy;
  two slots/byte capacity remain reserved for critical/terminal traffic.
- Each attempt gets a fresh ID and a new existing AEAD seal around the **same
  Signal ciphertext**. Sending another copy does not advance the Signal ratchet.
- Each delayed send checks current pair/key, subscribed path generation, and
  authenticated route expiry. Pair replacement cannot send a delayed packet
  using a closure over its former key. Registry and peer locks are not inverted.
- The existing pool maintenance tick handles at most 16 due messages per pass,
  with rotation and priority allowance. No per-message/per-contact worker or
  second durable business ledger is introduced. Retained bytes and observations
  are bounded. A physical attempt remains owned until PUBACK/disconnect.
- One logical publish token completes once, on the first successful physical
  PUBACK. That does **not** cancel scheduled copies or retire the business row.
- Authenticated `link_rx_stored` must match a local frame exactly, including
  pair, message, hash, traffic, attempt ID, broker and sender generation. Its
  return broker may differ. The existing ciphertext/key-bound outbox proof is
  checked before deletion. Failed storage cleanup leaves retries available.
- The real bridge verifies attempt metadata before ordinary ingress, then
  emits the attempt receipt only after durable message/ciphertext storage.
  Duplicate copies reuse the existing per-Signal-identity lane and inbox.
  No receipt-of-receipt or new Agent task is created for transport receipts.
- The existing authenticated Signal `delivery_ack` remains useful to message
  consumers. A successfully verified stored-message ACK also cancels unsent
  copies, but cannot fabricate a per-broker RTT sample because it lacks the
  original physical attempt ID.
- Both generated catalogs now require 20 verified samples before using the
  measured percentile to shorten/lengthen hedge delay. The cold value remains
  500 ms; min/max remain 100/2,000 ms. Observation rounds expire after 30 seconds;
  the existing durable outbox still owns subsequent retries and restart.

## Host Evidence

- Python: **338 tests passed**, zero failures/errors, 40.094 seconds.
  Log: `build/mqtt-hedge-python-v2.log`.
- Android pure JVM transport/codec suite: **143 tests passed**, zero failures,
  3.658 seconds. Log: `build/mqtt-hedge-host/tests.log`.
- Catalog generation check passed and **5 catalog tests passed**.
- Normal Gradle configuration was restored without the isolated init script.
  Main/test Kotlin compilation and **60 focused unit tests passed** (25 policy,
  35 existing Link protocol), zero failures/errors, build **3m 32s**. Log:
  `build/mqtt-hedge-normal-test-v1.log`. The 25 policy cases overlap the pure JVM
  run and are not counted twice. This build still excluded native-memory
  generation/embedded runtime packaging; it is not a full release APK build.
- The focused bridge/dispatcher suite includes the real `mqtt_bridge` send and
  receive entrypoints, `PeerRoutes`, actual AEAD, real SQLite, and the actual
  bounded `InboundRoutePool`. Physical brokers are deterministic fixtures;
  Signal JNI decryption is a fixture that stores the real application envelope.
  This is **not** a fresh JVM-to-S20U MQTT delivery test.
- Covered cases include lost receive ACK, alternate-broker ACK, three concurrent
  copies/one decrypt/one dispatch, generation changes, subscription removal,
  key rotation, corrupt ciphertext hash, wrong receipt scope/hash/attempt,
  failed durable commit, early PUBACK, duplicate callbacks, shared capacity,
  bounded tick rotation, shutdown cleanup, and outbox retry round expiry.
- A 10,000-row synthetic backlog query reported 15 ms. This is one local query
  observation, not a network result, p95, or 10,000 concurrent model tasks.

## S20U Evidence

Only `SM-G9880` / `R5CN319CESA` was operated. SM-T575 was not operated.

The isolated build compiled the actual main and Android-test Kotlin, retained
libsignal JNI, and used a plain Application without services/model startup:

```powershell
./gradlew.bat -I ../../tools/dev/mqtt-isolated/isolated.init.gradle `
  :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory `
  '-Pgalaxyssi.requireEmbeddedRuntime=false' --max-workers=2 --console=plain
```

Build passed in **3m 14s**; log:
`build/mqtt-hedge-isolated-build-v1.log`.

Device runner passed **51 tests**, zero failures, **7.73 seconds**, with final
`OK (51 tests)` and `INSTRUMENTATION_CODE: -1`. Log:
`build/mqtt-hedge-s20u-device-v1.log`.

Classes: atomic inbox (21), route persistence (6), existing outbox database (9),
transport receipt journal (8), cross-runtime wire/AEAD codec (3), and on-device
hedge policy (4). The last four verify the 20-sample gate, PUBACK versus stored
receipt, physical-slot ownership for raced controls, and wrong-pair/hash
rejection. Existing storage cases overlap prior checkpoints; do not add them
as 51 wholly new tests or call them 51 product end-to-end tests.

Both test packages were removed **after** the terminal successful result:
`com.galaxyssi.chat.mqttverification` and its `.test` package. The pre-existing
`com.galaxyssi.chat.test` was unchanged. Production `com.galaxyssi.chat` was
absent before and after this verification; this run did not uninstall it.

Retained artifacts (not shipping APKs):

- `build/artifacts/mqtt-hedge-s20u/verification-app.apk`
  SHA-256 `B42E94E862F580BCA8FD8C42EF589BA7F6899CB75C86B4837E55BB6C793E1115`.
- `build/artifacts/mqtt-hedge-s20u/verification-test.apk`
  SHA-256 `A1B4025FD43AA37B30FA3594CDBAFB4157AA1B0C62FDE3A5130EF9F7C61514B2`.

After restoring normal manifests/configuration, only the package/hash-verified
isolated APKs were removed from the ordinary Gradle APK output locations to
prevent accidental installation as the shipping application. Copies above remain.

No public broker was contacted by this checkpoint's tests. No production
identity, credentials, chats, or pairing records were read into a network test.

## Remaining Acceptance

The actual Android publisher still needs its symmetric framed-attempt scheduler
and receipt integration. Its current application receive path can persist the
Signal message and issue the existing stored-message ACK, but does not yet
provide the new attempt-attributed receipt/RTT. This is not an old-client
compatibility strategy; both shipping endpoints must be completed together.

Do not infer attachment bitmap durability, ten-window lifetime ownership,
cross-provider failure recovery, repeated p50/p95 improvement, background power,
or full arbitrary external-side-effect reconciliation from these tests.
These remain mandatory work under the original full goal.
