# Android compact chat shortcuts

## Scope

Android 1.5.77 (1360) keeps the approved inline shortcuts without replacing the
existing Agent header or composer:

- Restored product logo, brand title/subtitle, right-aligned conversation/model
  summary, and settings header, with the original dimensions and touch targets.
- Five inline actions above the composer: Feed, New, Chats, Photo, and Files.
- A bulleted-list Chats icon and independent unread dots for Feed and Chats.
- Small black unread dots anchored 2 dp from the text, with a light monochrome
  counterpart in dark mode. Icons align to the visible text center.
- No filled shortcut cards. The original more button appears for empty keyboard
  input and expands the existing action tray; Back closes the tray.
- Tray actions have separate IDs from inline shortcuts and share their handlers.
- Existing multi-window, new-conversation, model selection, camera, and document picker handlers.
- Contact chat, reminders, ASR/QNN, attachment processing, and transport remain unchanged.

The shortcut labels keep their configured text size. At narrow widths with large
accessibility fonts, the row scrolls horizontally instead of clipping or shrinking
the labels. Unread changes reserve their space and do not move the actions.
Scanning remains available from both the original action tray and Contacts.

## Verification

Device: Samsung SM-S9480 (S26 Ultra), covered by an in-place upgrade without
clearing chat, model, or pairing data.

| Check | Result |
| --- | --- |
| Debug APK and instrumentation APK build | Passed |
| AgentComposerUiPolicyTest | 8 passed |
| AgentChatShortcutBarDeviceTest | 4 passed |
| ReplyUnreadDeviceTest | 2 passed |
| ProactiveAttentionDeviceTest, homepage unread behavior | 1 passed |
| ProductLogoDeviceTest, home artwork and action | 1 passed |
| AgentConversationWindowsInstrumentedTest, original header actions | 1 passed |
| ScreenAssistantChatDeviceTest, shared composer, more menu, keyboard | 3 passed |
| ComposerEditingInstrumentedTest | 11 passed |
| Repository checks | Passed |
| 16 KB native library alignment | Passed, 74 AArch64 libraries |

The layout test covers 36 combinations of 320/360/412/800 dp widths,
Chinese/English/Arabic locales, and 1.0/1.5/2.0 font scales. It checks minimum
touch sizes, readable labels, action ordering, icon/text centering, text-anchored
badge positions, RTL placement, and stable geometry when badges change.

The earlier shortcut checks opened Chats, Feed, the Samsung camera, and Android's
document picker. Restoration checks additionally verified the original header,
keyboard-triggered more button, expanded tray, Back, multiline input, and send
control on S26U. Typing 123, Enter, and 456 produced two lines without sending.
The test draft was cleared afterward. No model request or contact message was
sent for these UI checks. All 23 selected instrumentation tests passed.

Local validation artifacts are in the ignored `build/compact-chat-validation/`
directory, including build logs, instrumentation logs, and S26U screenshots.
