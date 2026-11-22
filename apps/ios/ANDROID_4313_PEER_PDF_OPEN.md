# Android #4313: open received PDF attachments without exporting

Source: https://github.com/galaxyssi/GalaxySSI/pull/4313
Android merge: `7497d0023cd112d13636205c0bf2658e6eca8190`

## iOS mapping

- Normalize PDF aliases, MIME parameters and generic MIME types with PDF names.
  Preserve explicit non-PDF declared MIME types. PDF preview copies have a
  canonical `.pdf` extension even when the received file was named `.bin`.
- Resolve the existing local/decrypted attachment, prepare a private temporary
  read-only copy off the main actor, then ask Quick Look whether it can preview
  the item. Opening does not mark the artifact exported or saved.
- Require a readable regular local file, reject source symlinks and network URLs,
  use sanitized names and UUID-scoped directories, exclude copies from backup
  and protect their contents while the device is locked.
- Release the preview copy after controller dismantling, unsupported previews,
  stale requests, identity changes or foreground loss. Do not remove the original
  attachment. Keep existing encrypted-at-rest materialization policy unchanged.
- Show distinct localized feedback for unreadable attachments, unavailable
  previews, open failures and explicit save failures. A cancelled save is not
  reported as a failed save.
- When Quick Look cannot preview the file, offer **Save to Files**. This requires
  a separate user action and reuses the existing export picker. Unlike Android,
  iOS has no Samsung Downloads activity or Android read-URI grant; a built-in
  preview plus user-selected Files export is the platform mapping.
- Preserve the existing ZIP listing and compressed-export paths. Do not change
  Android, Desktop or app version numbers.

## Verification scope

Added XCTest source for MIME normalization, canonical/sanitized names, temporary
read-only copies, idempotent cleanup, original preservation and rejected remote,
missing, directory and symlink inputs. Tests were not executed, as requested.
Project structure, whitespace and Swift grammar checks are static checks only;
Xcode type checking, actual Quick Look rendering, Files interactions and device
behavior require a macOS/iOS environment and are not claimed here.
