# Android #4556 New User Conversation Model Defaults

Reference head: `ceb1e269929767ca5ac5921f8d85fc52e9e103a3`.
Independent iOS base: main `ee17e7cac043350e3f65c10ba025ecf55cde10c7`.
No unmerged Health banner, About, settings or search PR code is included, even though Android stacks this PR on #4554.

## Behavior

- Read the already-written default.selection preference as one existing Codable selection snapshot. A valid manual target carries its ID, display label, model variant and reasoning effort. Missing, malformed, non-manual or blank-target defaults produce Auto. Retain existing model-retirement normalization, per-target configuration keys, storage format and write behavior; no preference migration or new secret storage.
- Add explicit useRememberedSelection initialization. Save only for a new conversation with no existing stored selection; reinitializing/opening an existing conversation cannot overwrite it. Keep inheritDefault as the compatible user-inheritance helper, but stop using it indiscriminately for every Store creation path.
- User new-chat entry points opt in: home New session, session list, conversation hub, chat-to-Agent new session, explicit voice New conversation and an initial user composer/attachment session when none exists. The Store's general creation API defaults to no inheritance. Programmatically created, private Health, scanned-contact, news/attention/body-atlas, collaboration, recovery/retry and deletion-fallback paths retain their existing routing. The internal creation helper additionally blocks inherited defaults for agent-created/collaboration sessions.
- Existing manual and per-conversation Auto settings remain unchanged. User selectAutomatic already saves Auto as the future default; conversation-only Auto and rememberAsDefault=false selections do not replace the default. New selections are copied, not live links to the global setting. Unavailable manual targets remain manual and still face the existing routing/availability checks; no silent fallback or network dispatch is introduced by creation.
- Show the Android-aligned model picker label Default for new conversations, with its Simplified Chinese resource. Do not copy Android's version bump or change the main Agent header, output/composer, confirmations, permissions or remote protocols.

## Evidence

Inspect all eight Android changed files: model-selection settings, transcript creation, picker label, screen-assistant regression source, three language resources and Android-only build metadata. Port the user/programmatic initialization distinction; do not import the stacked Health/About changes.

Three new native fixture methods cover actual Store user/programmatic creation, complete target/model/effort and label snapshots, per-conversation versus global Auto, existing-chat preservation, malformed defaults and immutable initialization. Update three existing fixture methods for the intentionally changed new-user default while preserving screen/scanned-only choices. Fixture source only, NOT executed.

A dedicated source guard compares all other settings/picker and Store persistence/creation/switching code to the exact base; checks the six explicit UI opt-ins and retained programmatic callers, model transport/routing, resource keys and fixture wiring. Source/project/grammar checks are not Swift type checking, persistent UserDefaults/SQLite fault acceptance, UI interaction, unavailable-target behavior, account/scene concurrency or native/device proof. Windows has no Xcode. No native build, XCTest, CI watching, IPA, Android/Desktop edits or version changes. The overall port backlog remains incomplete.

Grammar audit: ten changed Swift files produce zero ERROR nodes. GalaxySSIViews.swift has three existing parser markers at #if DEBUG / DEBUG / #endif; their text and complete ranges are identical to main. They were compared, not removed or counted as a successful native compilation.
