# Stable reply identity acceptance

## Scope

The artifact campaign remains 100 cases and 1,100 planned turns. This change
repairs evidence capture, not production rendering or the definition of success.
Only the authorized SM-T575 (Active3) was used.

## Observed failure and verification

In `active3-handwriting-20260929-desktop1323`, turn 9 delivered a correct final
image and stopped its timer, but immediate capture retained an obsolete row ID.
The original failed observation remains unchanged.

A separate read-only audit (`capture-audit-1790679453209`) matched the frozen
report's conversation, turn, task, reply text and rich artifact identity to the
current final row. Original row `1798f785-aeaf-4eab-9d03-31ec96e4f5f5` became
`dacde4c3-a0fa-4e4d-9c5b-7f808728a17b`. The target was visible and focused, three
frames were stable, and the timer was stopped. Clicking the delivered thumbnail,
opening fullscreen and saving produced a new download (1000003336) with SHA-256
`51b345c8fdd183c84006cfbcab2f9fff41ae357e297d48a26a7035620ea61ef0`.
No model request was resent during this audit.

## Matching invariants

- Require the same nonblank conversation and turn, exact task and reply text.
- Reject non-assistant, streaming and approval rows.
- Accept unchanged rich JSON, or equal ordered rich blocks with identical
  non-file content and verified 64-hex artifact hashes, IDs, types, MIME types,
  titles and text. Only hydration-specific file locations/state may differ.
- Reset stable-frame sampling when the current matching row changes.
- Read the already-loaded UI window on the main thread, not the database.
- A missing target still fails; preserve a diagnostic screenshot when possible.
- Record initial and observed row IDs. Never rewrite historical failed captures.

Five identity device tests and three phase-timing device tests passed. The
18 Python catalog/timing regression tests also passed. This establishes the
specific identity repair, not a universal UI-restoration or grading pass rate.

Private transcripts, artifacts and screenshots remain outside Git.
