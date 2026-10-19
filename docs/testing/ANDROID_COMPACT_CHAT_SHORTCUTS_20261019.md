# Android compact chat shortcuts

## Scope

Android 1.5.75 (1358) implements the approved Agent chat navigation design:

- Compact product logo, conversation title, model selector, and settings header.
- Five inline actions above the composer: Feed, New, Chats, Photo, and Files.
- A bulleted-list Chats icon and independent unread dots for Feed and Chats.
- No filled shortcut cards, expandable Agent action tray, or duplicate more button.
- Existing multi-window, new-conversation, model selection, camera, and document picker handlers.
- Contact chat, reminders, ASR/QNN, attachment processing, and transport remain unchanged.

The shortcut labels keep their configured text size. At narrow widths with large
accessibility fonts, the row scrolls horizontally instead of clipping or shrinking
the labels. Unread changes reserve their space and do not move the actions.
Scanning remains available from the Contacts page.

## Verification

Device: Samsung SM-S9480 (S26 Ultra), covered by an in-place upgrade without
clearing chat, model, or pairing data.

| Check | Result |
| --- | --- |
| Debug APK and instrumentation APK build | Passed |
| AgentComposerUiPolicyTest | 9 passed |
| AgentChatShortcutBarDeviceTest | 3 passed |
| ReplyUnreadDeviceTest | 2 passed |
| ProactiveAttentionDeviceTest, homepage unread behavior | 1 passed |
| ProductLogoDeviceTest, home artwork and action | 1 passed |
| AgentConversationWindowsInstrumentedTest, compact header and new shortcut | 1 passed |
| ScreenAssistantChatDeviceTest, shared composer, typing, keyboard | 3 passed |
| ComposerEditingInstrumentedTest | 11 passed |
| Repository checks | Passed |
| 16 KB native library alignment | Passed, 74 AArch64 libraries |

The layout test covers 36 combinations of 320/360/412/800 dp widths,
Chinese/English/Arabic locales, and 1.0/1.5/2.0 font scales. It checks minimum
touch sizes, readable labels, action ordering, and stable geometry when badges change.

Manual device checks opened the conversation list, Feed, the Samsung camera,
and Android's document picker from their new controls and returned to chat.
Typing two numeric lines verified that Enter inserts a newline, the existing
send icon remains available, and all shortcuts remain above the keyboard.
Closing the keyboard restores the voice entry without a system focus rectangle.
No model request or contact message was sent for these UI checks.

Local validation artifacts are in the ignored `build/compact-chat-validation/`
directory, including build logs, instrumentation logs, and S26U screenshots.
