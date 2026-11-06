# Android Health original library search

The h27 library searches locally by file name, an explicit calendar date or
month, or a catalog metric name/alias. Dates match the import date or the
measurement date on a confirmed linked record, including authenticated
secondary sources. An unconfirmed OCR date is not treated as a confirmed
measurement date. Search is combined with the existing file-type and import
date filters. Photo and file counts describe the unsearched archive in the
selected date range; a search does not display those counts as match totals.

Archive metadata is decrypted in cancellable keyset chunks on a worker. Search
does not open original file contents or store a plaintext search index. Linked
metric and date matches are restricted to current confirmed records for the
local profile, with authenticated original IDs and digests. Search terms stay
in memory while navigating to an in-app child and are cleared when the library
goes into the background. The selected originals are persisted separately from
search and filter state.

## Device coverage

Run `HealthOriginalLibrarySearchDeviceTest` on an unlocked device. It uses
isolated encrypted databases and synthetic files to exercise multi-chunk
pagination, excluded review-only files, cancellation, primary/secondary record
links, deletion, in-place selection, and return from exact original details
and export confirmation. The preview freezes only the selected original
manifest; generation and sharing still require their existing explicit actions.
Use `-e originalSearchScreenshot true` to save a populated synthetic UI image.

Run the original library, export history, original removal, data hub, and
linked table-source tests alongside it to catch changes to shared pagination
and association behavior. This suite does not verify SAF across providers or
benchmark very large encrypted archives.
