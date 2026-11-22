# Android #4306: disconnect Desktop without deleting history

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4306

Android merge: `99f2995bdba565872ab6978b13683a32323ed16b`.

## Implemented in iOS

- A distinct disconnect action in Control Computer and Device Security. Existing
  delete/revoke actions retain their separate meaning.
- The confirmation captures the selected Desktop ID and full fingerprint, shows
  its name and fingerprint, and revalidates against exactly one currently paired
  link before changing anything. Display names are never identity keys.
- Mark only that Desktop's contacts history-only using the compatible optional
  `desktop_disconnected` field. Keep their IDs, messages, attachments and read
  positions; exclude them from active contacts, callable routing and new sends.
- Clear that Desktop's link, transport queues, transfers, Signal relationship,
  marketplace entries, control state, blob relay and remote Whisper registration.
  Refresh MQTT bindings without publishing `client_revoked`, since Desktop treats
  that notification as a request to delete message history.
- Both legacy and journal MQTT paths stop local business routing. Disconnect is
  local; it does not purport to remotely revoke a computer's retained copy of an
  old pairing. Re-pairing is required before the phone can send to it again.
- Include retained contact conversations in Archived Conversations, searching
  and counts, with no unread badge. They open existing persisted history read-only
  instead of creating a new Agent session. This does not delete or rewrite Agent
  transcript/session records or task execution history.
- Repeated destructive pairing cleanup cannot erase already history-only contact
  records. Late device/Agent metadata cannot reactivate an archived contact unless
  a current saved paired relationship authorizes restoration.
- Chinese text lives exclusively in the localization resource; English fallbacks
  are present on the new view and the read-only conversation state.

## Verification

Added XCTest source for exact identity/full fingerprint checks, duplicate/stale
links, same-name Desktop isolation, message persistence across restart and repeated
cleanup, archived discovery/read-only routing, late metadata and re-pairing, plus
backward-compatible contact decoding. Tests are not executed in this task.

Only targeted project structure, whitespace, incremental Swift grammar and scoped
localization checks are performed. Windows cannot compile/run Xcode or validate a
paired Desktop on an iPhone. No Android/Desktop source, version or IPA is changed.
The grammar tool already reports recovery diagnostics in the baseline large
coordinator file; those are compared separately from the new method, not presented
as a clean compiler result.
