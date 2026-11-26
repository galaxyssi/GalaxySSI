# Android #3025: ordered image reply presentation

Reference: cef237557f5f8f422f93832a535e3d63e3ba81ed (#3025), including its paired
Desktop changes to creation/reference order, linked-image spans and captions.
Incremental iOS parent: ba6ffe5c8330d170054042378fae4e26f3ae8cb1. This remains
part of #4610, not a duplicate Android-corresponding PR.

## Existing behavior and actual corrections

iOS already emits Markdown image blocks in encounter order with each alt text as
that block's title. Decoded Desktop text retains stable parent/part IDs, and
artifact de-duplication keeps the first position when upgrading a duplicate's
quality. This increment preserves those producers and fixes two concrete gaps:

- Reuse the existing Markdown link parser for a linked image's complete outer
  wrapper. Balanced source-URL parentheses and quoted/angled destination titles
  no longer leave outer punctuation/title residue. Require that the outer label
  consists of exactly the image, and keep existing safe image/source URL checks.
  No regular-expression replacement parser, new downloader or network access is
  introduced. Other Markdown scanning, limits and private-artifact stripping
  remain unchanged; this is not full CommonMark grammar equivalence.
- URI-only artifact identity previously lowercased the entire URL, collapsing
  distinct case-sensitive image paths or query values and losing one caption.
  Use URLComponents to normalize only scheme and host. Preserve path, query and
  fragment case; malformed/relative values retain their trimmed spelling. The
  shared rule also covers URI-only file/audio/video/gallery blocks. Existing
  digest/name identity, local-video identity, quality ranking and first-slot
  replacement remain unchanged. This is de-duplication, not authorization.

The actual renderer therefore keeps distinct case-sensitive images in reply
order, with captions still attached to their original blocks. The correction
does not infer captions from receipt filenames or reorder by an artifact hash.

## Remaining cross-platform boundaries

The Desktop producer owns generated-image receipt insertion order and validated
task-local image binding before transfer. It is not duplicated by an iOS receipt
directory scanner or by allowing arbitrary local/sandbox paths through Markdown.
iOS private-artifact scope, encrypted storage and integrity validation remain
unchanged. This increment does not add an independently verified local Markdown
caption-to-task-artifact rebinding path or certify cross-task/restart behavior.
Desktop credit windows remain backend behavior. Full linked-image grammar,
generated-image creation/transfer ordering, task-local caption, renderer/open/save
and end-to-end native acceptance are not established by source comparison alone.

## Verification boundaries

Eleven synthetic Swift methods are authored in a separately registered source:
wrapper parentheses/titles, markup order/captions/stable IDs, case-sensitive
paths/query/fragments, scheme/host normalization, duplicate quality upgrades,
unsafe/private markup, shared URI-only media and retained digest/local-video
identity. The branch now authors twenty-three new methods in total. No native
build or XCTest is run. Source guards compare the narrow changes with their
parent and retain surrounding parser, identity, storage and materializer code.
No device output, measured media equivalence, CI watching or IPA is included.

The historical image-reply-policy source guard was attempted and fails on
existing non-streaming engine fallback-language changes, not this parser/identity
increment. That engine is unchanged against the incremental parent; no older
fallback behavior is restored to make the historical assertion pass.
