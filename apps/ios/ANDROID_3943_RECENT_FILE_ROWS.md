# Android #3943: Recent Health File Rows

Reference merge: `b687358302662293cd6a648b8ba0b04422572a7b`.
Independent main base: `c6bad3465c673dfb2dcecb23b095185c129c7447`.
The existing iOS Data and Files hub was implemented in `76a4e1b5a`; this is a
presentation follow-up, not a duplicate full hub port.

## Production Difference

Android recent-file rows show the added date/time, source and size, followed by
a separate emphasized linked/unlinked/unavailable state. iOS omitted the date
and collapsed the status into one metadata line with a uniformly blue icon.

The row now shows the original import timestamp formatted using the configured
interface language and SwiftUI time-zone environment, source and native file-size
formatting. A separate semibold status uses green only for linked, available
files; unlinked or unavailable rows use the warning color. Images use an orange
icon and PDFs a blue one. Filenames retain two lines, metadata/status wrap, and
the full row remains an accessible combined tappable target.

Existing acquisition and availability classification, recent-four ordering,
counts, encrypted read/legacy migration, foreground clearing, cancellation,
source bindings and exact-original navigation are unchanged. Formatting reads
only the already projected metadata; it does not open or decrypt an original.
Existing import/export/backup/review actions and localization keys are retained.

## Verification Boundary

The source checker pins the reference Android row, complete reviewed iOS view,
ten negative source mutations and all three backing data/records/original stores.
Every other view line is retained outside the row/date formatter and time-zone
environment property. Project structure and whitespace checks are separate.

No Swift compilation, XCTest, simulator/device screenshots, actual DateFormatter
locale/time-zone output, Dynamic Type, accessibility or pixel/layout acceptance
was performed. No IPA, Android/Desktop, archive schema or permission changes.
This does not claim completion of every Android #3943 behavior or the wider port.
