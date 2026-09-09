# Artifact Delivery Queue And Download Retry

## Failure

A completed real Codex image-editing task returned its text and artifact card,
but the image payload remained queued with zero publish attempts. The same App
route had hundreds of ordinary messages pending. Ordinary ciphertext retries
occupied the existing four global / two per-route delivery window; terminal
text could use its reserved lane while artifact chunks could not.

Android consequently displayed the existing file fallback because no local image
was available. The download request set also coalesced the artifact indefinitely:
after the first attempt, later taps returned accepted without republishing until
a response or completed artifact removed the entry.

## Changes

- Desktop gives artifact chunks priority 90 and an independent small lane:
  at most two active artifact messages globally and one per App route.
- Broker-owned sends still count against that lane after the application ACK
  timeout. They are not duplicated while Paho owns their MQTT acknowledgement.
- Redelivery failure responses use the existing dependency-control priority so
  that an ordinary backlog does not hide a failed download response.
- Android coalesces repeated download/fetch taps for 30 seconds using monotonic
  time, then permits another request. Save intent survives that retry interval
  and is consumed when the artifact eventually arrives.
- Signal encryption, outer transport, pairing and artifact checks are unchanged.
  No history, pairing or durable outbox records are cleared to make the test pass.

Versions: Desktop 1.1.36; Android 1.1.22 (908).

## Automated Verification

- Artifact lane, durable delivery, batching and artifact ownership suite:
  62 tests and seven subtests passed.
- MQTT and task-result-outbox regression suite:
  175 tests and 22 subtests passed.
- Desktop checks: 29 tests passed; repository checks passed.
- Android debug build passed; all three `ArtifactRequestRetryGateTest` tests
  passed. They check tap coalescing, the exact 30-second retry
  boundary, delayed arrival/save intent, independent artifacts and immediate
  retry after publication failure.

The backlog regression uses two App routes with 100 ordinary messages each and
all ordinary slots occupied. Both images pass, each route gets only one artifact
slot, a second flush cannot add more, and an ACK releases only its own capacity.

## Physical S26U Verification

On 2026-09-09, the existing image-editing task was recovered using the real
Desktop/MQTT/App path, without rerunning the model or clearing phone state.
The Desktop artifact receipt changed from `pending` to `stored`; the phone
received a valid JPEG of 99,636 bytes. Its download SHA-256 matched the Desktop
transport digest. The existing configured Agent image compression was unchanged.

Screenshots confirmed the inline thumbnail, the full-screen image viewer and the
saved check mark. The image was present in `Download/GalaxySSI`. Private user
images and diagnostic screenshots are not committed to the repository.

This first physical check used the already installed Android 1.1.20 receiver with
Desktop 1.1.36. The Android retry behavior is a separate change; do not treat the
successful receive/save check alone as a simulated packet-loss or retry-timeout
device test. This is not a many-device throughput benchmark or a claim that all
historical ciphertext failures have been repaired.

The Android 1.1.22 (908) debug APK was subsequently installed on S26U with
`adb install -r`, preserving application data and pairing. Package inspection
confirmed the version, and launching `StartupActivity` returned `Status: ok`.
