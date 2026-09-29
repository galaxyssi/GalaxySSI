# Original Image Delivery Follow-Up

This change continues the unchanged 100-case / 1,100-turn artifact campaign.
Desktop is 1.3.22. Android production code and version are unchanged; the
Active3 instrumentation APK contains stricter format checks.

## Observed Defect

In the preceding A002 three-turn run, all nine preview files had PNG names but
contained JPEG bytes. The delivery layer compressed images over 100,000 bytes
without changing their artifact path/name. The test verifier accepted any
decodable image, so it could report delivery success without satisfying the
requested PNG format. Those historical reports remain intact and are not
reclassified as full passes.

## Changes

- New downloadable task artifacts preserve original bytes by default, both
  for negotiated Blob delivery and the bounded MQTT fallback. The change
  also applies to new deferred preparation and result regeneration.
- Large images are hashed and read in chunks; preparation no longer needs to
  allocate a full decoded/compressed image merely to deliver the original.
- Existing size limits, relationship ownership, integrity checks, receipt
  handling and cleanup policies remain unchanged. No protocol limits are
  raised to accommodate the change.
- Persisted pending records still use their recorded compression policy.
  Existing compressed transfers retain their previous ID/hash on redelivery;
  they are not silently replaced with a different original mid-transfer.
- Inline thumbnail generation remains separate and unchanged. Downloadable
  originals can consume more bandwidth and time than lossy 100 KB images.
  This fix does not claim that full-resolution transfer is faster on weak
  networks or add a new progressive-thumbnail protocol.
- The device verifier now checks decoded image MIME against PNG/JPEG suffixes,
  requires every image to satisfy format constraints, and enforces PNG for
  Office previews as already required by the frozen prompts. A valid image
  can no longer hide another malformed or mislabeled preview.

## Verification

138 isolated backend tests passed, covering byte-exact image chunks, route
selection, original and previously compressed redelivery, artifact ownership,
Blob publication/replay/deferred delivery, remote images and generated images.
The default-original test uses a valid RGBA PNG larger than the former image
budget, forbids whole-file reads and compression during preparation, and
compares reassembled bytes and hashes. Animated GIF and lossless WebP bytes
are also preserved.

The Android instrumentation build succeeded. Two tests passed on SM-T575:
JPEG bytes named PNG are rejected, actual PNG is accepted, mixed invalid
previews fail, and allowed PNG/JPEG annotation results remain supported.

Real A004 model/phone delivery is tracked separately below. Container checks
are not proof of content correctness, visual quality or full campaign success.

An additional 85 isolated regressions passed for large-file preparation,
contact attachments, Blob contracts, rich output, thumbnail compression and
Office preview. The large-file probes preserved the existing bounds: 152 MiB
contact preparation and a 1 GiB Blob boundary fixture each used about 2.1 MiB
of measured Python heap. These are local preparation measurements, not phone
memory or end-to-end transfer throughput. The 13 catalog/report tests also
passed; prompts and catalog hash were not changed.

## A004 Real Model Sample

Run `active3-original-images-20260929-desktop1322`, A004 turn 0, used the real
remote Codex provider on SM-T575. Desktop completed in 106944 ms; phone reply
terminal was 120173 ms, with another 122 ms in the file/save audit. The timer
stopped and the reply met the unchanged 180-second reply latency target.

One 1200x1600 PNG (67845 bytes) was received and saved, with matching download
hash. Visual review confirmed the data 168/192/190 and total 550, Chinese
labels, data table and chart. The model introduced a yuan unit absent from the
input, so this is not an unrestricted content-quality pass. The file is below
the old 100000-byte compression threshold; it verifies the ordinary path but
does not, by itself, prove the over-threshold defect is fixed.

## A002 Over-Threshold Real Follow-Up

The existing `active3-native-office-20260929-desktop1321` conversation resumed
at turn index 3 (add record D), without resending indices 0-2. This new turn
ran on Desktop 1.3.22 with the stricter test APK; the historical run-directory
name and old observations were deliberately retained. Desktop completed in
258954 ms, phone reply-terminal was 274251 ms, and the file/save audit took
334 ms. The timer stopped and this reply met the unchanged 300-second target.

All four attachments were received and saved: a 13076-byte XLSX and three
1132x1600 PNG previews of 118050, 164444 and 211822 bytes. Each PNG exceeds the
former 100000-byte threshold. Android's decoded-format checks and a separate
host Pillow inspection both confirmed PNG. Received/downloaded hashes matched;
the transport metadata original hash/size matched the received hash/size for
each preview. No PNG-to-JPEG conversion occurred in this real delivery.

Read-only XLSX inspection confirmed quantities 12/29/17/5, amounts
144/232/170/100, total quantity 63 and total amount 646. Formula ranges expanded
to four records and the native chart caches matched those four amounts. All
three received previews were reviewed; the complete chart and its four labels
were visible. The pre-existing unsupported currency assumption remains, and
no claim is made about arbitrary future-edit recalculation or all remaining
follow-ups. UI save-button interaction and complete performance phase timing
remain separate from the verified save API/hash checks.

The final test APK was rebuilt after adding the unsupported-extra-image
negative case, installed only on Active3, and its two format tests passed
again. No other phones or watches were operated.
