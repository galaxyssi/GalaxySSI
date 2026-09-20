# Wear OS contacts

Version 0.3.13 includes a separate person-to-person contact directory. Existing Desktop
Agents remain under Devices and the Agent selector. Contacts are also accessible
from phone setup, so a cloud API key or Desktop pairing is not required.

## Pairing

Open Contacts → My QR code on the watch. Scan it with the Android application's
existing contact scanner. The watch displays an incoming request; only a local
Accept action adds it to the approved contact list. Decline does not authorize
messages. Repeated broker delivery does not undo a local decision. A new QR offer
is required after a rejected or deleted relationship.

The watch compiles Android's actual `PhoneContactCard`, device identity and
relationship identity binding sources. Only the card's profile-storage lookup is
adapted to the watch. Compact signed `p2` QR offers, one-time claims, expiration,
control replay checks, identity-derived mailboxes and Signal bundles use the same
formats as Android. Pairing offers last ten minutes and can be refreshed.

## Messaging

Approved contacts use the shared three-broker pool, authenticated path resumption,
Signal encryption, durable encrypted inbox, ciphertext replay checks, chunking and
verified stored receipts. A broker PUBACK never marks a message delivered.
Messages and pending outgoing ciphertext survive process restart. A failed Signal
session requests the Android bundle-refresh control; pending messages are
re-encrypted under the recovered session without changing their message identity.

The watch validates the authenticated source/target and the direct-chat sender,
contact, route and conversation before accepting a message. Local storage and
notifications are separate from Agent tasks. No LLM or API key is involved.

## UI

- Round black screens, no clock on contact subpages, avatars and unread counts.
- Contact and message avatars compile Android's `GalaxySSIIdenticon` and drawable
  directly and use the full stored identity fingerprint, matching Android rather
  than substituting a nickname initial.
- Incoming messages on the left; outgoing green bubbles on the right.
- Text input and Samsung/system speech recognition followed by text sending.
- The Agent and contact screens use the same `WatchMessageComposer`: transparent
  input, identical dimensions and hints, pre-keyboard hold-to-speak, standard
  editing after the keyboard opens, and one slot for distinct send/more controls.
  The contact action page includes the same clipboard-list paste interaction.
- Selectable message text and delivery state.
- New messages do not replace the editor or move a user who is reading history.
- Current visible chat suppresses its notifications; other chats can notify.

This implementation supports text and speech-to-text. Binary attachment viewing,
voice-message playback and calls are not included; received attachment messages
display an explicit unsupported-attachment label. Screen-off delivery remains
subject to Wear OS networking and the user's background-connection setting.

## Verification

`WatchPeerProtocolTest` checks Android field compatibility and rejects wrong
sender/contact/route/conversation bindings. The watch also runs Android's contact
card and identity-route tests alongside the existing transport tests.

`WatchContactInteropTest` runs in a separate library test APK with isolated
identities. It checks signed compact QR parsing, pending approval, rejection
replay, local approval, both directions of native Signal encryption, receipt hash
validation, duplicate suppression, persistence and deletion. It never resets the
installed watch application's identity or contacts.

Contact cards use the same friendly device name and stable suffix as Wi-Fi setup.
Existing Android contacts retain their saved display name and can be renamed
without changing identity or chat history.

Removing a contact retires active routes while preserving identity-bound monotonic
route epochs and replay watermarks. Re-adding the same identity can resume with
an older peer that still remembers the previous route epoch.

The chat header contains a left-aligned back chevron and a single-line contact name, clipped to the available width without an ellipsis.
The header avatar, overflow menu, and contact settings/detail pages are removed.
