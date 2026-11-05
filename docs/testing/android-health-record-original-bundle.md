# Scoped Health Records And Originals ZIP

Record-only CSV, XLSX and JSON remain the default. Camera originals and uploaded
originals are independent opt-ins. Selecting either changes the output to a
ZIP, not to a different spreadsheet format or a portable backup. Its layout is:

- `records.csv`, `records.xlsx`, or `records.json`, containing the confirmed
  record scope with no embedded attachment bytes.
- `originals/<original-id>/<safe-name>`, containing the exact retained bytes
  for an available, selected source, once per original.
- `manifest.ndjson`, with scope, counts, the record entry, original links,
  SHA-256 digests, and one status for each distinct source reference. The
  measurement's original ID and digest identify its matching manifest row.

The original manifest is snapshotted with the records. Source metadata is
encrypted and paged; large original bytes are streamed. Review-only originals
are not eligible. Missing, unreadable and mismatched sources do not suppress
measurements and are disclosed before and after generation. Unselected originals
are distinguished from unavailable ones. If an included original disappears
after confirmation, a fresh preview is required rather than silently changing
the approved package.

The generated ZIP is encrypted in private app storage. Saving explicitly
creates a normal, unencrypted ZIP through the system picker. The app verifies
the destination's length and SHA-256 before marking the export saved. A failed
destination leaves the private artifact available for retry. The export is
not uploaded, automatically shared, or accepted as a restorable backup.

## Recorded Acceptance

Android 0.1.7.53 / 1466 was built and cover-installed on Tab Active3
(SM-T575), keeping existing data. All 86 focused device tests passed without
skips across the export UI, record and original exporters, backup, and privacy
storage. Native checks covered independent opt-ins, rotation, and the paged
confirmation's original and missing-source labels. Generated ZIPs were opened
and checked for byte-exact originals, source deduplication, usable CSV/XLSX/JSON,
and omission of excluded and review-only bytes. Tests also verified database
migration, invalidation on source removal, and rejection of a truncated
destination on readback.

Tests use only isolated databases and synthetic records and originals. The
record ZIP's physical system-picker/provider matrix and explicit sharing remain
separate acceptance items.
