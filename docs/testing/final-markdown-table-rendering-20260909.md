# Final Markdown Table Rendering

## Regression

On S26U, Android 1.1.30 (916) displayed a streamed monthly fruit table correctly,
then displayed its Markdown pipes and separator as plain text on completion.
The Desktop `build_rich_output` function wraps the unchanged answer in a TEXT
block. Android prioritized explicit rich blocks, but only expanded Mermaid
inside TEXT blocks, bypassing the existing Markdown table parser.

## Change

- Promote tables inside final TEXT blocks through the existing `fromText` parser.
- Preserve source metadata and stable derived block IDs across normalization.
- Keep the existing table view, horizontal scrolling, colors, and layout.
- Leave explicit code, ordinary pipes, and artifact blocks unchanged.
- Existing history benefits when decoded; no database migration or model retry.
- Android version: 1.1.32 (918).

## Verification

- Desktop wrapping reproduced using the real `build_rich_output` function.
- `AgentRichContentTest`: 18 passed.
- `AgentFinalMarkdownTableTest`: 5 passed. Covers stream/final parity,
  repeated normalization, stable IDs, metadata, fenced examples, ordinary pipes,
  multiple tables, and an accompanying image.
- Debug APK and instrumentation APK built successfully.
- S26U (`R5GL546G3LZ`, SM-S9480): both APKs installed successfully using `adb install -r`.
- `AgentFinalMarkdownTableRenderingTest`: 1 passed on S26U. Streaming, final,
  and normalized/reloaded fixtures each rendered a visible horizontal table
  with identical cell text and no raw Markdown separator.
- App relaunched successfully after instrumentation. No data clearing or pairing changes.
- ADB disconnected during the follow-up screenshot attempt, so a post-fix
  screenshot of the user's original fruit conversation was not obtained.

The instrumented fixture verifies real Android views but is not a new live-model
round trip or a complete reboot test. No other phone or running Desktop was modified.
