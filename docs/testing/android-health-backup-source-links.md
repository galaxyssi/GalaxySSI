# Android health backup source-link regression

- Export a version 2 package with primary and secondary OCR and table originals. Use 35 secondary links so the export and restore read more than one page.
- Restore into an independent self profile with equivalent existing data and existing originals whose local IDs differ. Verify remapping by digest, exact available bytes, and evidence metadata for missing bytes.
- Reopen and import the same package. Verify the existing record count, original count, and source link counts do not grow.
- Verify conflicts do not attach an incoming link to a changed local measurement. Force a failure at link insertion and verify that no measurement, original metadata, or receipt is published.
- Open a version 1 package and verify it restores without secondary sources. Use the native restore preview to confirm the new link count and separate user consent before writing.

Validated on Samsung Galaxy Tab Active3 (SM-T575), Android debug 0.1.7.58: 34 backup, restore and source-review tests and 87 table, migration, original-library and record-export tests passed without skips.

This change preserves secondary sources on current self measurements. Historical revisions, other profiles and manual conflict replacements are outside this increment.
