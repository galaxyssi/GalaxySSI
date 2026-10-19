# Android photo preview action alignment

## Scope

Android 1.5.78 (1361) aligns preview actions without changing attachment processing.
Previously, Crop consumed the remaining row width, Delete used a fixed width, and
Original used its intrinsic width. The mixed sizing pushed controls to the right.

Preview actions now have equal-width cells with centered content and a common
vertical center. Camera previews use four cells including Retake; image previews
use three; document previews keep their existing delete-only action centered.
The crop-mode toolbar, header, chat composer, encoding, and send behavior are unchanged.

## Verification

S26U (SM-S9480), in-place installation with existing data retained.

| Check | Result |
| --- | --- |
| Debug and instrumentation builds | Passed |
| Attachment edit/import unit tests | 19 passed |
| Editor device tests | 9 passed |
| Attachment routing device test | 1 passed |
| Repository checks | Passed |
| 16 KB native library alignment | Passed, 74 AArch64 libraries |
| Existing photo preview screenshot and interaction | Passed on S26U |

Layout assertions cover 320, 360, 412, and 800 dp widths in LTR and RTL.
They check equal cell widths, shared horizontal/vertical centering, touch sizes,
and bounds after quality changes and returning from crop mode. Functional
coverage includes real crop output, source preservation, recreation, Original,
Delete, Retake, and non-image files.

The first device run caught intrinsic-width icon buttons shrinking below their
original 48 dp touch width. Preserving explicit button widths fixed this; the
complete final run passed all 10 tests. Manual checks used the user's existing
photo draft, toggled Original on and off, entered Crop, and returned without
changing or sending the image.

Local build/test logs and screenshots are kept under the ignored
`build/photo-preview-alignment-20261019/` directory.
