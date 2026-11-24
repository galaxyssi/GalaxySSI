# Android #4391 iOS Port In Progress

Pinned Android merge: `165809fc9606ac1ff6b0df6eb9bee73286b415ea`.
This branch inherits formal iOS #4495, #4494, #4492 and #4491. No corresponding
iOS #4391 PR has been published yet. The eventual PR must use main and disclose
the inherited diff; incremental review starts at
`80e6cde79256a0c423efd07eab8b35630b7e5e4e` (#4495 head).

## Implemented

- Added the original 35 dedicated cutaways, with 140 new local explanations and
  49 new canonical anatomy links, from Kotlin-evaluated declarations.
- Expanded the pinned detail catalogue to 61 views / 279 features / 52 links.
  The original 26 views and their source drawable bytes remain unchanged.
- Imported all 744 additional vector paths with normalized quadratic geometry,
  group transformations, fill rules and retained PDF metadata.
- Imported and registered 347 exact English/Chinese pairs in AtlasExpanded.
- Activated revision 4391 with explicit revision 4389 archival reads, strict
  owner/source/count checks and original locator retention for every owner.
- Extended the existing view/zoom/layer restoration assertions to all 61 views;
  updated changed default muscle, skeletal, ear, nervous and valve expectations.
  XCTest source changes are not a claim that XCTest was executed.

## Source Checks

- Initial expanded source audit passed for all 70 changed source hashes,
  catalogue/feature/link identities, 678 combined resource pairs, source
  declaration equality and 1,152 original paths across all 61 PDFs.
- Source comparison proves original function assignments, function catalogue and
  physiology bindings are unchanged from the pinned #4388 source.
- Exact PDF geometry/transform/clipping operators passed the expanded audit;
  original 61-view declaration re-extraction and retained #4389 source audit
  also passed. These checks do not establish rendered pixel parity.
- Three changed Swift files parsed without grammar errors; project metadata and
  `git diff --check` passed. This is not Swift type checking.

## Remaining

- Finish exhaustive 70-file port dispositions.
- Check skin-layer navigation/independent function invariants and all affected
  historical XCTest source expectations; then submit one formal, non-draft PR.
- No Xcode/Swift compilation, XCTest execution, native gesture/restoration,
  screenshots, pixels, accessibility, device acceptance or IPA generation.
