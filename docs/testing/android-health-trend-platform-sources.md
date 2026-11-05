# Android health trend Health Connect sources

The Health Connect filter uses the stored origin of confirmed records. It
distinguishes source applications from Health Connect daily steps totals and
does not infer a hardware device or an application for an aggregate. The
selected origin is applied to the chart, its audit, and contributor pages.
The exact revision shows its recorded origin.

Existing encrypted records require no schema change or backfill. Discovery
scans the selected date and metric through bounded candidate pages and
keeps only the next 31 distinct origin keys. Private app-origin metadata
travels between screens and into saved state only in an authenticated
encrypted scope. Privacy history records the Health Connect source type,
not the app identifier.

Coverage uses isolated synthetic imports and checks source pagination,
aggregate labeling, malformed scope rejection, and native navigation to
an exact contributor revision. It does not establish performance for
very large custom date windows or validate a real provider installation.

All 85 trend, catalog, report, assistant, Health Connect, sync, and privacy
device tests passed without skips on Tab Active3 (SM-T575) with 0.1.7.69.
