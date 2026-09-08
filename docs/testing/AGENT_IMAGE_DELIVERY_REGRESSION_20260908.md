# Agent image delivery regression

## Reproduction

- Device: Samsung SM-S9480 (S26U), initially Android app 1.1.0 (886).
- A homework-editing result displayed two generic download cards.
- Desktop output enumeration included both an upright working preview and the final annotated image.
- The phone already held the final JPEG: 99,680 bytes, SHA-256
  `ca567deca6476980f2223e3eade421f5dd62eb4bd87ebf44138ed4a9918f7b6f`.
- Its original was 331,163 bytes. The reply described the original version,
  but strict local lookup compared it only against the compressed version.
- The Desktop task source had been removed after the phone acknowledged storage.
  Requesting redelivery therefore could not repair this presentation mismatch.

## Changes

- Legacy lookup accepts either complete transmitted identity or the original
  hash/size pair recorded during authenticated, integrity-checked ingestion.
- A source-version fallback requires a hash. Mixed versions, different artifact
  IDs, and mismatched scoped identities remain rejected. Blob transfers retain
  their strict current-version checks.
- New legacy reply metadata carries the actual transmitted hash and byte count,
  alongside original metadata.
- Explicit final output links select deliverables before transport preparation.
  Multiple explicitly linked outputs remain available. Without matching final
  links, output enumeration is preserved; filenames such as `preview` are not
  blindly discarded.
- Agent images reuse the existing full-screen image viewer with zoom and save.
- Existing messages and files are not deleted or rewritten.

## Automated verification

- 48 Desktop tests: rich output, task workspace, artifact delivery, blob publication.
- 23 Desktop tests: MQTT agent recovery and deferred artifact publication.
- Android store tests use unique artifact URIs and remove only their own files.
- Android app and instrumented APK build succeeded (13m 25s).
- App 1.1.4 (890) was installed over the existing S26U installation; no app reset.
- The original conversation now displays inline thumbnails of both historical files.
- Tapping the annotated image opens the full-screen viewer with its save control.
- Saving produced a JPEG with a localized filename under `Download/GalaxySSI/`; its SHA-256 exactly
  matches the received JPEG above. This uses local bytes, not Desktop redelivery.
- Both S26U instrumented tests passed after correcting test-provider path isolation:
  chunk reassembly/content-URI reading, and compressed-version matching/saving
  with rejection of mixed hashes/sizes, wrong artifact IDs, and wrong turn scope.

## Scope

This does not regenerate a deleted full-resolution Desktop original. Existing
compressed images remain the verified bytes already delivered to the phone.
It does not retroactively remove intermediate attachments from old transcripts.
