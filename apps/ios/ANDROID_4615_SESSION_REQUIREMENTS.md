# Android #4615: conversation-owned session requirements

Android merge: e3c3705409845dd83dd75ba906402d782879b455.
iOS integration base: 4d24af48643352ea03c5603f4f1b160afbeacc85 (main).

## User workflow

Long-press an owned user message and select text. The native edit menu includes
Session requirements on iOS 15 (legacy menu) and iOS 16+ (edit-menu delegate).
The message context menu also provides a full-message fallback. Selection seeds
an editor only when there is no saved requirement. Save, edit, cancel or remove
the note; no original message is rewritten and no permanent header is added.
The limit matches Android's 320 UTF-16 units, with character-safe seed truncation.
Chinese labels live only in the existing localization resource; English labels
use the established fallback mechanism.

Only active, owned Agent user messages are eligible, not imported/merged source
messages, replies, system rows, read-only generated requests or pending voice
transcripts. The editor captures identity, plaintext generation, conversation ID
and expected saved value. Switching conversations/identities or clearing private
plaintext dismisses it. Save revalidates live access/identity/active conversation
and refuses stale expected values, deleted rows, merged owners and oversized
input. Removal saves an empty note explicitly; cancellation performs no write.

## Persistence and model paths

The note uses user_session_requirement inside the existing encrypted conversation
payload. A BEGIN IMMEDIATE metadata patch changes only this field. It preserves
draft status, original messages, title, summary, model selection, privacy settings,
activity timestamps and ordering; cache publication follows a successful commit.
No separate plaintext preference store, key, schema column or permission is added.

Phone planning and restored planning overrides read the exact outgoing owner.
Missing owners or a mismatched recovery context never inherit another session's
note. Current edits/removal override an older journal snapshot's preference before
planning. The compact planner goal reserves the note even when long dialogue is
omitted. Global-context exclusion preserves the local preference while still
excluding global data. Notes are quoted preferences, not tool authorization;
existing host permissions, consents and tool execution checks remain unchanged.

Desktop projection includes the structured field even when the note is the only
context. Embedded context-envelope delimiters are JSON-escaped without changing
decoded content. Direct cloud request preparation includes the exact saved note
for both streaming and non-streaming callers and image turns. Local user-model
and managed-browser prompt preparation includes it too. The canned fast local
reply is bypassed when a saved note requires model interpretation. New requests
read current metadata, not a memoized context. Encoded non-empty notes change the
planning identity; empty notes omit the new context field so old planning journal
fingerprints remain compatible. Existing metadata/backups decode missing fields
as empty.

This does not cancel an already dispatched model request or rewrite an immutable
tool-loop checkpoint midway through execution. Existing durable replay and
side-effect ownership rules remain authoritative; the note is not permission to
repeat an effect. This PR does not claim the complete Android backlog is ported.

## Verification boundaries

Fourteen deliberately synthetic Swift methods are authored for UTF-16 limits,
legacy decoding/fingerprints, encrypted metadata reopen/removal, draft retention,
stale/deleted/merged writes, private/global exclusion, structured transport and
delimiter round trips, exact recovery ownership, selection eligibility, changed
planning identities, native selected-text callbacks, planner compaction and
store identity/active-conversation rejection. They are not compiled or executed.

The focused JavaScript guard checks actual source wiring, transaction gates,
legacy and modern menu paths, resource keys, project registration and unchanged
encryption/permission implementations. It is not native/UI/crypto/runtime proof.
No Swift build, XCTest run, live model/network, device acceptance, CI monitoring,
full repository check or IPA. Android/Desktop code and versions are untouched;
iOS 15 minimum is retained. No raw reports or private evidence are committed.
