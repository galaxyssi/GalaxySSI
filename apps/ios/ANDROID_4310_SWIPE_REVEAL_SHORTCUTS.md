# Android #4310: swipe-reveal Health and Scan on Agent home

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4310

Android merge: `42a7a7ef6f9f05827a2c37a0ee376d9a0f08fc70`.

## iOS behavior

- Keep Feed, New, Chats, Photo and Files in order, with Health and Scan appended.
  Feed remains present with zero unread items instead of disappearing when empty.
- Measure each localized label at its Dynamic Type size and reserve its icon/dot
  space. Distribute spare viewport width only among the original five actions;
  the appended controls do not shrink those initial items to fit seven at once.
- Large labels keep their natural width and overflow horizontally, not shrink or
  wrap into the composer. Preserve unread-dot space even when the count is zero.
- Minimum action dimensions are 48 points or the larger configured touch target.
  The row height follows the caption metric. No separators or new attachment-tray
  buttons are introduced; the input row, keyboard and tray implementation are unchanged.
- Health uses the existing owner-scoped Health Center via hidden home navigation,
  with identity-based view recreation to avoid keeping another account's state.
  Scan calls the same existing home scanner callback used by the attachment tray.
- Feed now uses the existing home Insights route so every shortcut is a command
  whose activation can first reset the native horizontal scroll position.
- A row-local UIKit resolver binds only the containing horizontal scroll view.
  Activation immediately sets its content offset before invoking the callback.
  Logical start accounts for LTR/RTL and adjusted insets. Rebinding the same view
  does not reset a user's swipe; a new view or direction change resets to start.
- Native SF Symbols, accessibility labels/IDs, help labels and Chinese resource
  keys accompany the new controls. Health's icon follows the red health accent.
- Group the hidden navigation destinations so each builder group stays within
  the iOS 15-compatible child count. No iOS 17-only scroll-position API is used.

## Verification scope

Added XCTest source for actual action ordering, viewport allocation, localization
and Dynamic Type measurement, touch targets, unread space, bad input, RTL/insets,
native-scroll callback ordering, idempotent binding and missing-native-view actions.
These tests are not executed in this task. A source audit also checks the real
composer routes and unchanged input/tray method bodies.

Only targeted structure, whitespace, scoped localization and incremental Swift
grammar checks run on Windows. No Xcode build, on-device horizontal gestures,
accessibility run or native screenshot is claimed. No IPA, Android/Desktop source
or version changes are included.

Apple API references:
- https://developer.apple.com/documentation/uikit/uiscrollview/setcontentoffset(_:animated:)
- https://developer.apple.com/documentation/uikit/uiscrollview/adjustedcontentinset
- https://developer.apple.com/documentation/swiftui/scaledmetric
