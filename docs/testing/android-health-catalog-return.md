# Android health catalog return navigation

Opening a catalog child preserves the current search, section, category,
keyset page, and visible row anchor for the return. The anchor contains
the row identity and offset, so an insertion above it does not move the
reader. If the row is no longer present, restoration falls back to the
previous pixel offset; an emptied later page returns to the preceding page.

The catalog drops decrypted result views on stop and queries the current
page on return. Foreground record changes refresh that page without loading
the entire history or replacing the visible page with a loading placeholder.
The search text and page anchor are never placed in
saved state or on disk. A direct stop, screen-off, or the process UI-hidden
callback clears them. Only non-sensitive section and category controls
are saved for recreation.

The native device tests use isolated synthetic databases. They exercise
catalog to populated trend to revision and back, record-page anchoring
with insertions while the detail and the catalog are visible, and the
UI-hidden clearing callback.

On Tab Active3 (SM-T575) with 0.1.7.66, all 70 catalog, trend, overview
and assistant regression tests passed without skips on the final APK.
