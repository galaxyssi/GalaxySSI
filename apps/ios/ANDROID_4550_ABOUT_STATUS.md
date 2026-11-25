# Android #4550 About Page

Reference head: `16bdaa3e06a5126a5c7b77d1bcdb579cba2633a4` (open Android PR when inspected).
Base: main `ee17e7cac043350e3f65c10ba025ecf55cde10c7`.

- Compare all three Android changes: About product UI, four device regression fixtures, and Android-only version metadata. Do not copy Android's version bump into iOS.
- Remove the duplicate product hero/subtitle/version from iOS About. Start the scroll content with Product, and show the installed bundle version once in a non-action value row, not a single-line shrinking badge.
- Use two flexible text columns normally, unlimited vertical wrapping and Dynamic Type fonts. Accessibility text sizes stack the value below the labels. Version text remains selectable; there is no navigation action or disclosure on this row. Retain the existing version lookup/fallback without inventing Android's installed version or changing release metadata.
- Preserve protocol navigation, security navigation, open-source repository action, localization, page header and scroll behavior. Do not change shared rows used elsewhere.
- Source checker compares the exact retained sections and version getter against main, confirms the pinned Android intent and local wrapping/accessibility branches. Grammar and project checks are source-only. Android's device assertions motivate the layout but do not prove it on iOS.
- No native build, XCTest/UI execution, screenshot/device acceptance, CI watching or IPA. Exact pixel parity and narrow/large-text rendering remain unverified on Windows.
