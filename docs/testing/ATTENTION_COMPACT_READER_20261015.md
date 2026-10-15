# Compact Following Updates Reader

## Scope

- Android 1.5.19 (1302), based on merged main including the discovery storage/ANR fix.
- Home entry, reader title, settings entry and notification channel share the
  following-updates naming. The home count is the actual unread total, not a
  fixed example value.
- Remove the permanent All / Unread / Saved strip. The top-right native menu
  contains All updates, Unread only, My saved items and Following settings.
- Put the unread count beside the page title. Do not expose a partial preview
  count as a complete inbox count.
- Preserve continuous loading, in-place expansion, bilingual titles, font sizes,
  read-color stability, bookmarks and reading-position restoration.
- New-arrival notices overlay the bottom of the list instead of reserving or
  inserting a strip that changes the reading viewport height.
- A filter explicitly selected during initial loading takes precedence over a
  previously persisted filter, including an explicit selection of All.

No collection policy, model routing, user preferences, source data, saved items,
or communication encryption is changed by this UI work.

## Verification

Executed on 2026-10-15:

- Debug APK and Android test APK build successfully.
- 40 JVM tests pass: timeline (14), attention policy (12), title policy (11),
  local storage policy (3).
- 18 device tests pass on Samsung S20 Ultra (SM-G9880): 14 targeted reader/UI
  cases and 4 isolated local-storage cases. Synthetic storage is isolated from
  the real inbox. Tests make no explicit model requests.
- New cases cover compact-layout geometry, menu labels, Chinese naming,
  early filter selection, partial counts and filter restoration.
- Existing cases cover stable scroll/expanded content during updates, offscreen
  collapse, automatic read and undo, regular enlarged typography, bilingual
  updates, light/dark title colors, saved state and the homepage entry.
- Kotlin source-size, localization and whitespace checks pass.

The final APK was installed in place on S20U. Manual checks confirmed the home
entry, compact feed, four-item menu, settings navigation and in-place expansion
with the user's existing 1.5 font scale. System navigation and the existing
screen-assistant overlay remain unchanged. No S26U or watch was modified.

This validates the UI update, not the accuracy or completeness of every news
source. Items with only a fetched headline continue to disclose that limitation.

## Header and Menu Follow-up

Android 1.5.20 (1303) keeps the page title centered independently of the unread
count. The count occupies only the space between the title and the action; long
counts can ellipsize without moving the title, and accessibility retains the
full count. The more action uses the design's five-dot cluster. A custom anchored
menu replaces platform-dependent checkbox styling with leading icons and one
thin green check for the selected filter. Unselected rows have no empty boxes.

Verification on 2026-10-15:

- Debug APK and instrumentation APK build successfully.
- 26 JVM tests pass: timeline (14) and attention policy (12).
- 10 targeted S20U device tests pass, including three new header/menu cases.
- Header geometry covers Chinese and English, font scales 1.0 / 1.5 / 2.0,
  widths 320 / 384 / 600 dp, and counts from empty through Int.MAX_VALUE.
- Menu tests cover all filter callbacks, settings navigation, exactly one bare
  check, and raster checks for the five dots and unboxed check glyph.
- Reader regressions cover filter restoration, naming, homepage visibility,
  stable scroll and expanded content, automatic read, bookmark undo and
  offscreen collapse.
- The APK is installed in place on S20U. The real 1080-pixel-wide screen places
  the title at x=444..636, centered at x=540, with the count independently beside it.
- Kotlin size, localization and whitespace guards pass. No inbox records,
  model settings, system font settings, S26U or watch installations are changed.
