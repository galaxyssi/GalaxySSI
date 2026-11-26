# Android #3304: Original-page iOS Files export

Android merge: `3f2b6bf9ba3bb706fe1bf7edbadbda437c6c0c0a`.
iOS comparison base: `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.

## Actual production integration

The existing phone public-HTML preparation already captures the fetched original
bytes and privately stores a non-executable `.html.txt` source. That remains
unchanged. Previously even an explicit Files export reconstructed all prose
first, followed by a separate image list. It could not preserve original order.

For an existing explicit save/export request with captured HTML and the concrete
URLSession provider, build a static original-DOM document using the existing
SwiftSoup dependency. Retain the ordinary readable model attachment, export ID,
private raw source archive, consent path and Files exporter. Replace only the
pending user export's bytes and give it an `-original.html` suffix. Other providers
and a failed original-document build retain the previous readable export.

Lazy article images are embedded before optional stylesheet decorations. Keep
stylesheet cascade order and resolve relative stylesheet images against the
stylesheet's final redirected URL. Asset requests reuse the existing bounded
HTTPS transport, address/redirect/content checks and original public-web
permission/consent. They cannot extend the existing preparation deadline.

Limits: 8 MiB source, 8 MiB per asset, 24 MiB aggregate accepted assets, 128 unique
asset attempts, eight optional decoration attempts and 48 MiB serialized output.
Repeated resources share a byte cache. Repeated embedded copies also spend a
separate encoded-output budget. Failed resource requests are not retried in the
same build. Images, styles and media that cannot be saved are marked incomplete.

Publisher HTML is parsed as data, never executed. Remove scripts, frames,
embedded content, forms/inputs, refresh/base metadata, event and non-allowlisted
attributes. Remove active/dynamic media, SVG images and unsafe anchor schemes.
Keep only allowed raster data images, rewritten inline CSS and public-HTTPS
anchors. A generated CSP blocks automatic remote resource loading, scripts,
forms and base overrides; links remain explicit user navigation. English and
Chinese incompleteness notices use existing localized resource bundles.

## Boundaries

This implements the explicit user Files export path, not Android's WorkManager
automatic background Downloads archive. It does not introduce an iOS background
archive queue, resume/retry lifecycle or automatic Files writes. A deadline may
leave resources missing; the notice and missing-asset metadata say so. Fonts,
dynamic media and unsupported/escaped CSS may not reproduce publisher layout.
The old raw source archive remains separate, not a safe page to execute.
Full Android #3304 parity and the overall backlog are not claimed complete.

## Verification limits

Six synthetic Swift fixture methods are authored in the existing registered
test file: DOM order/lazy images, dangerous content and side channels,
stylesheet order/redirect base, failed-resource deduplication/request bounds,
invalid input, and actual asset-loader permission/deadline/private-host/byte
boundaries. They are not compiled or executed. The source guard checks
the actual explicit-export call site and new loader and compares the complete
surrounding preparation/provider/old fixtures/project/resource sources with the
pinned base after the declared additions. It does not prove DOM, CSS, network,
compiler, device, fault or privacy acceptance.

No native build/typecheck/XCTest run, live network test, CI monitoring or IPA.

Source verification: the new original-page export scope guard, its JavaScript
syntax check, iOS project structure check, changed-source/document literal-Han
placement and diff whitespace checks passed. No full repository or historical
Web scope-guard pass is claimed.
