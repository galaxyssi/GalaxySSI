# Codex native image delivery

## Failure and fix

The S26U request for a clownfish image completed with text but no attachment.
Codex had generated a valid image; the App Server adapter only forwarded the
`imageGeneration` progress event. Native generated images were not written into
the GalaxySSI task workspace. The earlier remote-image work handled explicit
HTTP image references, not native image results.

Desktop 1.1.44 captures native image completion into task-owned output files,
then uses the existing artifact selection, rich-image and MQTT/Blob transport.
The Android UI and APK are unchanged.

## Boundaries

- Capture is bound to task, Codex thread, turn and item identifiers. Late events
  from another thread or turn are rejected by the existing adapter routing.
- Base64 and supported image data URLs are validated before decoding. A saved
  path fallback must match the current thread's Codex generated-image directory
  and event filename; arbitrary local paths are not accepted.
- Images are capped at 12 MiB, 32 million pixels and 8 captured results per run.
  PNG, JPEG and WebP are verified and decoded before publication.
- Atomic task output and SHA-256 receipts support duplicate events, terminal
  snapshots, interrupted-task recovery and explicit result replay.
- The original Codex-generated file is preserved. The existing Agent attachment
  transport may compress its task-owned copy; this change does not alter that
  policy or weaken Signal/MQTT encryption.
- Missing, corrupted or unwritable generated images fail finalization instead
  of accepting a text-only success claim after a native image event.
- This is not a universal semantic detector for every unsupported claim made
  without a native image event. It specifically closes the observed native
  image delivery gap.

## Automated verification

- 252 backend tests passed in the broad regression run, covering Codex tasks,
  remote images, rich output, artifacts, MQTT routing/recovery and Blob paths.
- After adding the native chat-fast-path and disk-failure regressions, all 67
  focused Codex/image tests passed again.
- The final 19 native-image tests also passed after adding malformed-receipt
  handling, including JSON values with the wrong structure or missing identity.
- Final broad regression on the complete change: all 256 tests passed in
  53.295 seconds. Desktop was restarted with the final implementation; health,
  MQTT readiness and all 10 subscriptions were confirmed again.
- 29 Desktop Node tests and the Desktop structure check passed.
- Coverage includes duplicate output suppression, incorrect thread/turn/path,
  corrupt and oversized data, missing files, failed generation, missing terminal
  notifications, recovery snapshots, native result replay and encrypted Blob
  publication from the normal chat fast path.

## Real task verification

- Used the official Codex `thread/read` API to recover the existing completed
  clownfish task `0070c954-3925-355f-ad1d-318bcf593626`, without starting another
  model turn or generating a replacement image.
- Recovered one 1536 x 1024 PNG, 2419878 bytes. Read, validation and task artifact
  registration took 1733 ms including starting the read-only App Server client.
- Original SHA-256:
  `babfe0292653f0a072e083ad0144e8b4fd4032ebfe5eef5f69d295ec495c20cd`.
- Desktop 1.1.44 started successfully, MQTT connected and all 10 subscriptions
  became ready. Explicit replay of the original task returned
  `agent_task_result_republished`.
- The delivery ledger recorded the intended phone's authenticated `stored`
  acknowledgement with the matching transport-image SHA-256. The existing
  compression policy was enabled for this Agent artifact.
- A subsequent workspace cleanup warning was logged after the stored receipt
  was persisted. It does not negate the storage acknowledgement; cleanup is not
  claimed as verified here.

## Remaining device acceptance

S26U USB disconnected before the after-fix visual check. Only SM-T575 remained
attached and was not operated. Thumbnail rendering, fullscreen viewing, Save
and a fresh model-generated task remain pending on S26U. A transport storage
acknowledgement is not a substitute for these UI checks.
