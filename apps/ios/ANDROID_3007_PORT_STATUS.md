# Android #3007 Public Search Parsing

Reference merge: `65655f0c79c6ab04121150229a65b089180f82f2`.
Incremental predecessor: #4534 at `492bebe922013c2f707b38e4ddc849a655deba68`.
This is a partial port, NOT completion of all #3007 behavior.

## Implemented

- Replace the actual URLSession public-search regex link extraction with an inert SwiftSoup DOM parser. Raw HTTP search stays separate from WebKit article rendering. Fixed dependency 2.6.0 uses Swift tools 5.0; exact upstream tag commit is pinned in Package.resolved and the app target links the product.
- Read result heading anchors/cards, exclude scripts/styles/navigation/headers/footers/advertisements, deduplicate fragment-normalized destination URLs, and return bounded result titles/excerpts. Small bare-anchor adapters remain supported.
- Read Baidu's direct `mu` destination only from its owning c-container heading, not unrelated metadata. Decode same-engine URL query redirects and Bing URL-safe base64 redirects; preserve unrelated external query URLs. Reject credentials, invalid base64, non-HTTP(S) schemes and oversized destinations. Existing actual-fetch public-host/HTTPS/redirect/body/time policies are unchanged.
- Recognize Baidu security verification title/captcha redirects as `source_verification_required`, not successful empty evidence. If other sources work, expose unavailable provider/error codes alongside successful results. Excerpts are returned as both excerpt and snippet for existing consumers. Explicit allowed-host filtering precedes final result truncation.
- Three native regression fixture sources cover cards/snippets, ad/navigation/script exclusion, duplicate fragments, redirects, scheme/credential rejection, direct Baidu card ownership and source verification. They are NOT executed.

## Sogou Image Search Follow-up

- The actual model image-search call previously forwarded image verticals into ordinary web endpoints and the intelligence layer discarded image fields. Image-only requests now use the Android reference's `pic.sogou.com/pics` public endpoint. Explicit unsupported image engines or mixed image/non-image selections fail clearly, without silently substituting generic web results. This implements Sogou only, not all Android image engines.
- Parse the exact inert initial-state script as JSON with SwiftSoup and JSONSerialization; do not execute publisher JavaScript or use WebKit. Examine at most 100 rows, validate absolute source/image URLs, require HTTPS media, reject localhost/.local names and credentialed URLs, deduplicate actual images and preserve original-versus-thumbnail fallback and bounded dimensions. Search results explicitly say their bytes have not been downloaded. Existing actual-fetch private-host/network restrictions still apply when content is opened.
- Return images, lead image, source page and excerpt through raw provider and intelligence evidence projection. Deduplicate images rather than source pages, retaining multiple images from one page. Plain-text document cache entries cannot satisfy image requests; image cache persistence is not implemented and those requests deliberately bypass the text cache rather than losing image identity.
- Carry unavailable-source diagnostics through the upper intelligence metadata, not just the raw provider. Added native parser and actual registry-to-evidence fixture sources, including two images from one page and unsupported-engine no-network checks. NOT executed. Existing Markdown image display is reused via model-selected image URLs; this does not claim real download, relevance, viewer/save, UI or device acceptance.

## Remaining Work

The full Android PR also changes other image adapters/relevance, dynamic renderer isolation/recovery, web evidence verification, request budgets, maintenance/index atomicity, transcript/context paths, model tool-loop spans and UI timing. These remain explicitly incomplete; no Android/Desktop/version/credential changes or IPA generation. Source integration and fixtures are not runtime acceptance.

`check-public-search-parsing-scope.cjs` pins all Android changed files and checks the actual parser call/metadata/project wiring while keeping HTTP/browser transport and model-loop/service files unchanged against the predecessor. These are source contracts, not Swift type checking or runtime acceptance. Windows has no Xcode: no dependency resolution/build/XCTest, live search, WebKit failure/recovery, UI, network latency or device claims. Android measurements do not transfer to iOS.

#3017 was also inspected as a candidate: its changed-file list contains Desktop backend/version and evidence files only. No separate Android source implementation was added by that PR; it is not counted as an iOS port here.
