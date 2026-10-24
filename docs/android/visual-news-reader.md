# Visual public-news reader

Public news is stored separately from private chat attachments. The article database
retains its plaintext Chinese body for existing reading and Agent handoff paths, plus
a per-article structured document for presentation. No whole-feed JSON is created.

## Content contract

- Keep headings, paragraphs, source emphasis, lists, quotes, table rows, code, image
  captions, and image order. Scripts and original page CSS never execute in the reader.
- Prefer images embedded in the article; use an OpenGraph image only when no usable
  body image exists. Do not generate an illustration or substitute unrelated images.
- Translate text blocks through the existing local translator while preserving image
  URLs and structural types. Chinese articles do not invoke a translation provider.
- Key excerpts are verbatim sentences from the body, not an AI-generated summary.
  Do not remove uncertainty or promote an unverified source claim into a verified fact.
- Exclude submission acknowledgments and subscription boilerplate from the preview.
- Preserve complete JSON-LD article text when the visible DOM contains only a teaser.

## Loading and upgrades

- Collapsed rows query only indexed article metadata, preview, and cover information.
  Full documents are loaded only when the reader expands an article.
- Long bodies append 30 presentation blocks at a time. Oversized text blocks are split
  at sentence boundaries; remaining content is available through Continue reading.
- Image downloads and decoding use two background workers. Only visible images start
  loading. Recycled views cancel their work and ignore stale callbacks.
- The public image disk cache is limited to 64 MiB and decoded bitmap cache to 8 MiB.
  Individual downloads are bounded to 8 MiB; TLS and existing public-host checks apply.
  Images are decoded at display-appropriate sizes and can open in the shared zoom view.
- Existing articles stay readable and retain their identity, ordering, and read state.
  Viewing an old row requests a low-priority structural upgrade; it is never republished
  as new news. Failures retain the old body and use the existing persistent backoff.
- Metadata enrichment may refresh collapsed rows, but never rebuilds an expanded
  article while the user is reading. Reopening it adopts the enriched document.

Queue statistics remain available on the news settings page rather than occupying the
reading timeline. Provider attribution and source verification status are retained.

## Verification

`AttentionArticleDocumentTest` covers extraction order, image validation, captions,
source qualifiers, boilerplate, structured translation, JSON-LD, and serialization.
`AttentionVisualArticleDeviceTest` covers metadata-only queries, migration, durable
enrichment, backoff, stale callbacks, typography, and bounded article rendering.
Its optional `attention_visual_live=true` mode enriches a small selection of existing
public articles and verifies real source-image downloads and decoding on the device.

### S26U verification, 2026-10-24

- Built Android 0.1.6.9 (1385) and installed in place without clearing application data.
- 85 targeted JVM tests passed, including the bounded media download contract.
- The final device run passed 20 tests with one optional URL-driven translation test
  skipped. Live public-article image extraction and decoding ran successfully.
- Real-source validation caught a text-only fetch API being used for images. The
  reader now uses the existing bounded media download API, retaining TLS, public-host,
  MIME, size, cancellation, and decode checks.
- The existing `AgentRichContentPinchZoomTest` replaces MainActivity's entire content
  view, which conflicts with asynchronous startup hydration and caused a test-host
  failure. The independent `AgentMermaidDiagramRenderingTest` viewport test passed
  pinch and pan validation instead. No unrelated MainActivity changes were made.
- Native memory sources were unchanged; the build reused the previously verified
  native memory library while rebuilding Android code and tests.
