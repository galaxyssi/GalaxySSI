# Desktop tool evidence import coverage

The iOS consumer imports authenticated Desktop observations into encrypted
collaboration history. Android #3323 distinguishes completed pagination
from full provider coverage and reports originals too large for the phone.
The iOS `desktop_evidence_list` response exposes the same distinction:

- `provider_history_complete` is always false.
- `import_coverage` reports a known member's current import generation.
- `index_final` means the authenticated index was exhausted, not that the
  provider captured all events or that every original was imported.
- `oversized_originals_skipped` counts observations skipped above 8 MiB.
  Such observations stay on Desktop and have no phone-side byte receipt.
- `skipped_count_complete_for_indexed_range` is false when an import resumed
  from an older checkpoint that did not count earlier skips. The reported
  count is then a lower bound.

The cursor and coverage commit together, after supported-size originals
from the authenticated index page are saved. A failed attempt or replay does
not increment the count. Coverage is visible only through the existing
same-run scoped recall authorization and current observer generation.
This is operational provenance, not independent verification.
