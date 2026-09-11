# Desktop remote image delivery

## Problem and scope

S26U could display some DeepSeek image results, but a Codex result for a fish
displayed an unavailable preview. The image-rendering path was present. The
Desktop and phone did not have equivalent access to the image origin.

The reported Animalia WebP URL returned HTTP 200 on Desktop, but HTTP 403 with
`Cf-Mitigated: challenge` using the same application user-agent on S26U. A Sogou
image control returned HTTP 200 on the phone. This identifies an origin/network
access difference; it does not prove that every failure is caused by a VPN.

Only Desktop production code changes. Android UI, message schema, pairing,
encryption, thumbnail viewer and save controls remain unchanged. Desktop version
is incremented from 1.1.42 to 1.1.43. No Android APK was rebuilt or installed.

## Delivery path

1. Parse explicit Markdown images and `galaxyssi-rich` image/gallery blocks.
   Ordinary hyperlinks, escaped examples and fenced code are not downloaded.
2. During cumulative progress and terminal status snapshots, expose source links
   without asking the phone to render remote images.
3. Download public HTTPS image bytes on Desktop using its operating-system route.
4. Validate decoded format, dimensions and byte limit. HTML challenge pages and
   corrupt content never become image attachments.
5. Persist verified bytes and a source receipt under the task runtime workspace:
   `tasks/<task>/outputs/web-images/<scope>/<content-hash>.<extension>`.
   Downloads are not placed inside the source repository.
6. Replace remote image references with normal task artifacts. Reuse existing
   finalization, encrypted MQTT attachment or negotiated Blob delivery, recovery,
   scoped metadata and phone-owned storage.
7. Android renders its existing local image card, full-screen viewer and save
   action. The source URL remains provenance metadata, not the image load URL.

Failure is explicit and retains a source link. A failed remote image does not
prevent successfully downloaded images from being delivered. The Desktop itself
must be able to access the source; this is not a general proxy or a way to bypass
an origin's authentication requirements.

## Integrity and resource bounds

- Require task, client route, conversation, client turn, source message and
  execution generation. Missing scope disables automatic remote-image rendering.
- Isolate receipts by that scope and reply content. Deduplicate repeated URLs
  and identical bytes. Cached content must still match its recorded SHA-256.
- Recheck execution ownership after download and before publication. Manual
  replay also rejects a changed generation or result snapshot.
- Existing durable Blob replay and deferred delivery take precedence over new
  download preparation. Previously accepted replies are not silently rewritten.
- HTTPS/443 only, normal certificate verification, no cookies or credentials.
  Reject private, loopback, link-local and multicast destinations. Pin a validated
  DNS address while keeping hostname verification and SNI. Validate redirects
  independently and explicitly close response streams.
- Up to eight unique images per reply, four download workers, twelve in-flight
  or queued downloads, 12 MiB per image and 32 million pixels. A shared 30-second
  download budget bounds publication waiting; OS DNS resolution can outlive an
  individual socket deadline. Pool capacity remains bounded during such delays.
- Directory creation is briefly serialized per task to avoid Windows concurrent
  non-strict path-resolution prefix races. Network reads remain parallel.
- Image MIME overrides do not depend on Windows file associations. In particular,
  small WebP files are not sent as `application/octet-stream`.
- Existing Agent image compression policy is preserved. Download validation does
  not recompress the source, but the attachment layer can still compress larger
  Agent images. Saving means saving delivered bytes, not promising an uncompressed
  original in every case. Contact image compression policy is unchanged.

## Automated verification

From `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python -m unittest test_remote_reply_images test_remote_image_delivery test_rich_output test_rich_image_result_matrix test_artifact_delivery test_blob_artifact_publication test_blob_artifact_final_callback test_mqtt_agent_recovery test_mqtt_task_turn_routing test_task_latency test_artifact_delivery_ownership test_image_transport test_blob_artifact_replay test_blob_artifact_deferred test_blob_artifact_peer -v
```

- 189 tests passed in 52.270 seconds. These use isolated workspaces and mocked
  network publication, not a real model or phone receiver.
- The multi-image download case was additionally repeated 50 times on Windows:
  all 50 passed, with eight accepted downloads and two explicit count-limit
  outcomes per reply. This specifically exercises directory/content-write races.
- `npm run check`: 29 Desktop tests passed; structure check passed.
- `git diff --check`: passed.
- Full local test log: `build/reports/desktop-remote-image-unit.log`.

## Real network check

Test source:
`https://s3.animalia.bio/animals/photos/full/original/fish4433-flickr-noaa-photo-library.webp`

- Desktop download, validation and attachment preparation: 1.828 seconds.
- One validated WebP, 92,230 bytes; transport MIME `image/webp`.
- Transmitted bytes equal downloaded bytes for this below-threshold image.
- This was a real HTTPS fetch with normal certificate validation. Files were
  created in an isolated temporary runtime workspace and removed by test cleanup.
- Desktop was restarted with this branch, and health reported encrypted bridge
  readiness, MQTT connected, and 10/10 expected subscriptions active.

## Pending S26U acceptance

The automated debug-goal launch was blocked by the execution environment. No
alternative launch mechanism was used to bypass that denial. The user was asked
to send a normal Codex image question on S26U. No new test task had arrived when
this record was written.

The following are still pending on the new real MQTT response, not claimed as
passed by the unit suite:

1. Select Codex Agent on S26U and request the fish image in a new conversation.
2. Observe a local thumbnail, without a phone request to the blocked origin.
3. Open the image, zoom, save, and compare the saved bytes with the received hash.
4. Reopen the conversation and verify the image still loads locally.
5. Request several images and verify there is no duplicate image card or turn
   crossover; check a source failure produces a useful notice and source link.

Existing historical external-link messages are not automatically migrated.
