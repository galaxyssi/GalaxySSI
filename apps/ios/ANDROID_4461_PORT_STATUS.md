# Android #4461 iOS Port

Source: Android #4461, merge `c0be10a58c873cea52d3f60caf071cf36ec0a4af`.
Incremental predecessor: iOS #4524, commit `b957e686a77b21fc72325f9370f7ac8a23155623`.
The branch is cumulative and targets `main`; its complete main diff is not an independent #4461 change.

## Implementation

- Read interactive article title/body readiness without waiting for broken or lazy images. Require three equal body signatures and recheck navigation generation, page address and signature before using a snapshot.
- Preserve text/image ordering and trailing prose using the existing inert DOM helper. Remove active and interactive content. Browser snapshots use the displayed DOM without a second HTML fetch.
- Hand direct-fetch verification or missing-body responses to the visible ephemeral browser. Verification requires explicit Continue; the original 300-second lifetime remains in effect. Browser readiness has a 120-second observation deadline.
- Keep a single export lease across direct fetch, browser verification and rendering. Cancellation retains ownership until workers terminate and removes cancelled outputs.
- Bound image work to four seconds/eight MiB per image, 35 seconds/48 MiB per export, and 128 distinct cached remote assets. Each fetch receives a fresh invocation deadline. Decode bounded thumbnails rather than retaining full-size decoded images.
- Stream native CoreText/image PDF output to a private temporary file. Preserve missing-image positions and accurate missing counts, source and static-copy footer. Refuse image-only articles with no decoded content. Validate file/page bounds before publishing a protected final file in Downloads/GongZhongHao.
- Import eight changed Android string pairs and four unchanged reference pairs into dedicated localized source tables; keep five iOS Files/foreground adaptations separate. No Android notification, MediaStore or background-service claim.
- Keep canonical article URL validation, shared network/SSRF/redirect/MIME kernels, generic webpage previews, generic PDF imports and science extraction rules unchanged.

## Evidence And Limits

`ANDROID_4461_SOURCE_INVENTORY.json` pins eleven changed Android files plus one unchanged archive dependency. `ANDROID_4461_PORT_COVERAGE.json` records every file disposition.

Source/resource contracts and synthetic DOM fixtures cover signature/address changes, unloaded images, sanitization, ordered text/missing-image blocks, verification and body absence. `check:ios` checks project structure. Native lease/PDF XCTest fixtures are registered but not executed.

Windows has no Xcode. No Swift type checking, XCTest execution, native PDF generation, Chinese glyph/layout/pixel validation, real network timing, WebKit verification flow, physical-device acceptance or IPA build is claimed.
