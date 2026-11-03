# Visual Artifact Delivery

Android and Desktop version: `0.1.7.13` (Android version code `1426`).

## Contract

The model chooses presentation from the user's intent. The framework does not
route a task by matching an animation keyword or substitute Desktop execution
for phone execution.

- A playable inline animation preferably uses a `galaxyssi-html` fence containing
  the original unescaped program. It can also use an explicit `html` block in `rich_output` or
  a `galaxyssi-rich` fenced document. Its code must be self-contained.
- Requested source code uses `presentation: "source"` and an ordinary code
  example. Ordinary HTML fences are not automatically executed.
- A video requires an actual encoded media artifact and verified phone tool
  receipts. HTML, an acknowledgement, and an encoder's mere availability are
  not an MP4 deliverable.
- Answer-only envelopes preserve both their rich output and any declared
  completion requirements. Changing response shape cannot drop file obligations.

The contract is shared by ordinary cloud replies, compact image/history planning,
and the full phone-supervised loop, including Desktop-hosted reasoning providers.
It distinguishes native inline playback from Linux/Playwright rendering.

## Storage and Presentation

Declared inline HTML is materialized as a hash-addressed private attachment using
the current attachment store. This main branch intentionally removed local
attachment AES encryption in `7e2654ee7`; the file is private, not encrypted at
rest, and the metadata now reports `app_private` rather than claiming Keystore
encryption. This change does not restore a removed global storage policy. The stored file has an HTML
display name, MIME type, byte count and SHA-256. A completed assistant transcript
can carry the declaration in its text; it need not arrive through a separate
provider-specific rich-output field.

The supervised completion path saves declared HTML before accepting completion
and puts the compact file reference in its durable result metadata. Recovery can
open the complete program even if the checkpoint's textual preview is truncated;
it does not depend on a foreground UI having rendered the response first. A
storage failure is a failed delivery, not a completed animation.

The existing isolated WebView renders the delivered attachment directly in the
chat and exposes the normal file controls. It has no file/content access,
network loads, external assets, forms or device bridge. Backgrounding or recycling
the attachment preview releases the renderer; returning creates a fresh preview.

Executable inline blocks are rejected rather than silently truncated when they
exceed the inline working set or contain an unfinished document/script. Larger
documents use the existing workspace create/export path. Old complete HTML code
examples retain their source and gain a user-initiated isolated playback button.
The button does not mutate their transcript or launch a Linux browser.

## Failure and Recovery

Browser service startup occurs before dispatching a page mutation. A startup
lock, failed startup, or expired readiness observation now reports
`executed: false`; an existing service is not killed or duplicated. A missing
receipt after actual dispatch still means an unknown outcome and requires
reconciliation. This does not remove effect verification or allow blind replay.

A previous cloud-interruption projection checkpoint cannot permanently hide a
later reintroduced paused/waiting session. Reconciliation checks the session's
actual terminal state while preserving active requests, user pauses, committed
replies, and execution history. It does not restart a provider or replay tools.

## Validation

Validation on 2026-11-03:

- Android: 339 selected JVM tests passed; application and instrumentation APKs
  built successfully. Prompt budgets were kept unchanged.
- S26U (`SM-S9480`): version `0.1.7.13` was installed in place. All 15 headless
  completion, materialization, cloud-watchdog and control-protocol tests passed.
- Runtime browser: 40 tests passed; three optional browser integrations skipped.
- Desktop: 109 checks passed. Repository structure and policy checks passed.
- A real, pinned DeepSeek query completed in 152,607 ms without Desktop fallback.
  Its 13,974-byte HTML attachment was read back from phone-private storage;
  its size and SHA-256 matched the delivery metadata. No user task was resubmitted.
- That exact program and the preserved original 12,434-byte DeepSeek program
  both passed desktop-browser pixel-motion, pause and replay checks at widths
  390 and 900, without script errors. These are host checks, not Android UI proof.

The opt-in MP4 run did not produce a final deliverable within the test's
180-second deadline and was cancelled by the harness. It stayed on DeepSeek and
the phone execution path, repaired tool-argument and resource-dependency plans,
then reached a cold Linux capability probe. No MP4 was exported or claimed as
verified. This is an outstanding live-video acceptance gap, not a passing test.

The phone remained keyguard-locked during this run. Android on-screen canvas
motion and preview background/re-entry are also not claimed as passed; the
corresponding instrumentation acceptance tests remain available.

The real-provider test can require `expected_visual_delivery=html` or `video`.
HTML acceptance checks private delivery and changing canvas pixels; MP4 acceptance
opens the exported video and decodes a frame, not just a filename or MIME claim.
