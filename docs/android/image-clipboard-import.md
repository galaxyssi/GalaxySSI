# Image clipboard import

Android and Desktop version: `0.1.7.12` (Android version code `1425`).

## Android

The Agent and contact composers previously accepted text only. A clipboard or
keyboard image did not enter the attachment import/editor path.

Both inputs now register an AndroidX receive-content listener for `image/*`.
The custom editor routes native paste actions through that listener and
advertises image MIME support to keyboards through `EditorInfoCompat` and
`InputConnectionCompat`. Plain text retains native editing behavior. Mixed
clipboard text is inserted at the current selection; image URIs are not inserted
as literal input text. Text containing an image URL remains text, not a remote
image download.

Imports capture the originating Agent conversation or contact ID before any
asynchronous work. The existing importer copies provider content into private
attachment storage off the UI thread, then opens the same editor used by file
selection. Cropping, default compressed delivery, original-quality selection,
cancel and explicit send are unchanged. Pasting an image does not submit an
Agent request or send a contact message.

IME read permissions remain held until metadata access and the private copy
finish, including failure and destroyed-activity paths. Rejected non-image
clipboard content cannot enter the picker's immediate document-send branch.
An unavailable clipboard image gets a localized import error. No clipboard
listener polls or watches background clipboard changes.

### Copying an image

The contact image menu no longer uses the text/attachment-name copy branch.
Long press carries the exact image attachment and resolves the message by its
stable ID, so multiple images and list reordering cannot select the wrong image.
Text and other attachment copy behavior is unchanged.

Agent images, gallery items and full-screen viewers also expose image Copy.
Copy reads the original encoded image stream, not the displayed thumbnail, and
creates an independent private cache snapshot. The system clipboard receives an
image MIME type and a readable content URI, not a filename, path or URL string.
The snapshot remains readable if the original message file is deleted; native
paste then enters the same crop/original-quality editor described above.

Copies and cleanup run off the UI thread. Clipboard publication must succeed
before old snapshots are pruned; the currently published image is protected.
Unpublished snapshots are discarded on failure or destroyed activities. Source
attachments are never deleted by clipboard cleanup and no public Download copy
is created. Clipboard snapshots are transient cache, not message storage.

## Desktop

Loaded image context menus now offer image copy using Electron's native
`webContents.copyImageAt`, including contact bubbles and the image viewer.
The contact copy/delete menu no longer substitutes a filename for an image
when the pointer targets loaded image pixels.

Paste accepts Chromium file lists, item-only files, and native bitmap clipboard
data when Chromium exposes no file. Native images are staged as PNG through
the existing attachment staging and preview tray. Agent and contact composers
share this path. Clipboard text/HTML without an image representation remains
text; a copied image URL does not cause a network download. Pasting never sends
the attachment automatically.

Late staging and metadata responses are checked against their originating
conversation/contact and privacy-clear epoch. A stale response cannot refill
another conversation's attachments or a cleared preview cache. Discarded staged
files use existing owned-temp cleanup.

## Verification

- Android debug APK and test APK built successfully; 34 related JVM tests passed.
- All 38 S26U device tests passed on `0.1.7.12`: both input layouts, mixed text/image content,
  keyboard image commits, owner-bound editor launch, private-copy survival after
  deleting the provider cache source, original/compressed quality, crop controls,
  text selection and hold-to-talk.
- The existing long-press test now waits for startup draft restoration, isolates
  OEM remote text classification, and restores the original draft after testing.
  Production touch/selection behavior was not changed by that test adjustment.
- All 109 Desktop checks passed, including image menu commands, clipboard payload
  variants, text fallback, late result isolation and preview-cache clearing.
- The isolated Electron UI smoke for the previous increment passed with native clipboard testing enabled:
  actual image copy, contact paste, no-file native bitmap fallback and text URL
  paste. Screenshots verified attachment previews. Common clipboard text/image
  formats were restored afterward.
- Windows smoke cleanup waits for child stdio closure and uses bounded async
  retries for temporary directory locks. Cleanup remains restricted to the
  generated smoke directory under the system temp root.

The four new image-copy device tests passed, covering original encoded bytes for inline/local
Agent images, source deletion, exact image selection after list reordering, and
the real contact Copy menu followed by native paste into both editors. The
round-trip test verifies image MIME, absence of clipboard text, and matching
SHA-256 after deleting the selected source file. Pasting opens the existing
editor with original quality off by default and does not send a message.

S26U received an in-place `0.1.7.12` (code `1425`) install without clearing chats, pairing or model data.
No S20U or iOS device claim is made. Test screenshots and logs remain in ignored
build/smoke directories, not in source control.

Implementation references: [Android receive-content APIs](https://developer.android.com/develop/ui/views/receive-rich-content)
and [Electron image-copy API](https://www.electronjs.org/docs/latest/api/web-contents#contentscopyimageatx-y).
