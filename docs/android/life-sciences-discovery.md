# Life-sciences news and educational knowledge

The existing `protein_life_sciences` subscription covers protein fundamentals and
design, structural biology, cells, drug discovery, DNA/genomics, RNA, gene editing
and synthetic biology. Existing subscription IDs, enabled states, custom scopes,
saved articles and read states are preserved.

## Discovery

- Fifteen professional RSS/Atom feeds cover the University of Washington Institute
  for Protein Design, MIT, Nature specialist journals, PLOS, eLife and arXiv.
- Sixteen independent search facets use alternatives rather than requiring all
  biological terms to appear in a single story. Shared-feed filtering includes
  plural forms, named methods, DNA/RNA terminology and Chinese equivalents.
- Life-sciences news admits the preceding 90 days, retaining original publication
  dates. Other news and research topics keep their existing age windows.
- Twenty curated educational entry points include the PDB-101 Molecule of the Month
  archive, NHGRI genetics glossary and fact sheets, the IPD beginner guide, eleven
  MedlinePlus Genetics chapters, two NCI indexes, and OpenStax Biology 2e,
  Microbiology, and Anatomy and Physiology 2e. Only same-host article paths from these registered indexes
  qualify as undated knowledge; arbitrary pages do not bypass news age checks.

An index is a discovery source, never a readable article. Its links enter the same
URL-deduplicated persistent article queue as news. Educational records carry a
`knowledge` flag and zero publication time. The reader labels them as science
explainers and shows collection time, not a fabricated recent publication date.
Full-page titles replace generic glossary link labels before translation.
PDB-101 uses its explicitly marked reading region, excluding portal chrome and the
standalone bibliographic list while preserving scientific prose, discussion and
figures. The original-source link retains access to the bibliography. Optional
JavaScript sharing notices do not hide a complete static article; actual access
challenges, paywalls and script-only shells remain rejected.

The textbook adapter parses the public, embedded table-of-contents JSON without
executing JavaScript. It admits numbered sections only, validates the book slug,
and bounds tree depth and node count. Exercises, account links and other books
are not discovered. The reader extracts the actual chapter region, retains
figure captions/credits and the publisher's license/author attribution, and keeps
the original-source action. Downloaded publisher content is not bundled in the
application or committed to this repository. Textbook licenses remain those of
the source, including noncommercial/share-alike restrictions where specified;
they are not replaced by the application's software license.

## Illustrated reading

Educational articles with source images open in a Figures view, with a Full text
tab retaining the entire translated chapter in reading order. Figure sequences
preserve adjacent captions, shared multi-panel captions, nearest headings and
source attribution. Missing captions fall back to the source image description,
not an invented model explanation. Images retain their original labels; Chinese
machine-translated descriptions are displayed separately. The view does not
claim to redraw or independently verify scientific diagrams.

Figure view appends at most four images at a time. Image acquisition remains
visibility-triggered, cached and bounded. Science thumbnails use fit-center
rather than cropping labels; full-size figures retain pinch zoom. Text-only
articles have no empty Figures tab. Ordinary news rendering is unchanged.

Coverage includes molecular/cell biology, proteins, biochemistry/metabolism,
genetics/genome engineering, RNA, developmental biology, physiology, immunology,
microbiology, neuroscience, regenerative medicine, pharmacology and oncology.
This is a broad curriculum plus continuing discovery, not a claim that every
biological topic or publication has been collected or medically validated.

## Bounded processing and persistence

Publisher feeds and educational indexes are interleaved, in batches of at most
four endpoints. Index responses retain the existing 2 MiB limit, certificate
validation and source/host backoff. Successful index scans have a durable 24-hour
checkpoint; interrupted or failed scans can retry. Repeated discoveries cannot
duplicate an article or downgrade its educational classification.

Body acquisition, structured extraction and Chinese translation remain in the
existing bounded article worker. Only completed readable Chinese bodies enter the
feed. Blocked, inaccessible, paywalled and body-less discoveries stay pending or
retrying, rather than appearing as headline-only items. Large discovery counts
therefore do not imply that all articles are already translated or published.

Public article storage stays unencrypted. Schema 8 adds a single knowledge flag to
schema 7 without resetting existing bodies, queues or inbox read/bookmark state.
Schema 9 adds resumable per-article staging as described in
[public article recovery](news-processing-recovery.md), without replacing published bodies.
Neither discovery nor indexing requires a Desktop Agent or sends user chats to
an external model.

## Verification

Unit tests cover topic relevance, bounded catalog rotation, dates, relative links,
URL deduplication and scope checks. `GALAXYSSI_LIFE_SCIENCE_FIXTURES` can point to a
directory of HTTPS-fetched public HTML files named by SHA-256 of the source URL
plus `.html`, enabling production-parser checks against real catalogs and bodies.
Publisher HTML is not committed to the repository. Device tests cover database
migration, durable scan checkpoints, failed-index retries and deferred publication.
Textbook and figure tests additionally cover malformed/foreign TOCs, traversal,
multi-panel captions, source attribution, non-cropped thumbnails, bounded view
counts, tab switching and text-only fallback. The opt-in
`attention_knowledge_article` device argument verifies a real registered chapter
through extraction, translation, publication and bitmap decoding, without using
fixture text as published content.
