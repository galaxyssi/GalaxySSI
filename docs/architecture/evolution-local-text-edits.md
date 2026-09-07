# Local incremental source edits

Desktop 1.0.59 adds generic `edit` and `append` actions to the private local
implementation loop. Previously its only mutation tool was whole-file `write`.
Real Qwen3-1.7B attempts repeatedly removed existing documentation while trying
to append a section, even after receiving the preservation requirement.

## Tool contract

- `edit` takes a relative path, an actual `expected_revision` from a read,
  `old_text`, and `new_text`. The old text must be nonempty and match exactly
  once. Empty new text deletes the selected span. Matching is literal, not regex.
- `append` takes the path, an actual read revision, and only the text to append.
  It does not regenerate or normalize the existing content.
- `write` remains available for new files and intentional full replacements.
  The model chooses the action; there is no project-specific task classifier.

The host preserves every byte outside the requested change, including UTF-8 BOM,
CRLF, and an absent final newline. Ambiguous/missing spans, stale or invented
revisions, invalid UTF-8, and out-of-scope mutations return structured observations
without applying the requested edit. The model can reread, select a more specific
span, or choose another action. There is no cumulative action-count limit.

All mutations use the existing bounded text-file envelope, sibling temporary
file, flush/fsync, mode preservation, and atomic replacement. A second source
path/digest check before replacement detects changes during edit preparation.
This is not an OS-level compare-and-swap against arbitrary external writers;
resource-level multi-writer locking remains a separate requirement.

An immediate duplicate append using the old read receipt is rejected because
the file content changed. This is not a claim of exactly-once side effects after
process death: a new loop still needs to observe persisted content before
deciding whether to repeat an action.

## Loop and observations

JSON action schemas expose both operations. The model prompt explains their
semantics and recommends localized edits for localized changes. Real success
observations mark them as applied writes, and durable/UI projections retain the
operation and error type without source content. Edit arguments are omitted from
the bounded rolling model history after their observation; rereading remains
available when more source context is needed.

The independent task acceptance and publication gates remain in place. Providing
an append tool does not prove that every model will select it correctly or that
a candidate satisfies every user requirement.

## Validation

Focused tests cover exact replacements, deletions, multibyte text, CRLF/BOM
preservation, stale append retries, ambiguous/missing spans, source changes while
preparing an edit, total-size validation, temporary-file cleanup, schema fields,
and a model-driven error/read/append observation loop. Controlled fixtures prove
tool behavior, not real-model competence.

The retained real Qwen3-1.7B task resumed after the controlled restart under the
same task ID, `evolve-dag-6a4d5d53bb135d4ce5b95f4838a74f13`, attempt 4. The model
chose `read`, then `append`, then `finish`. Candidate
`0a443eb1d78891cbdd1d75f3c090c1aa9ed117d5` has one insertion and no deletions,
compared with 15 deleted original lines in each of the previous two attempts.
The model did not regenerate the source file, and the host did not write the
requested document content on its behalf.

The candidate is still incomplete: it appended the requested sentence but
omitted the section heading required by the original campaign objective. The
local semantic reviewer incorrectly returned pass and the task reached
`waiting_approval`. The isolated harness did not publish it. This is a real
negative case for the next acceptance improvement: applicable parent-goal
requirements need explicit coverage, not merely presence in a context field.
Tool-level byte preservation is verified; complete goal acceptance is not.

Local checks passed: 383 evolution regressions, a final 41-test local-tool suite
(including overlapping-match rejection), 70 CLI/session/DAG tests, 29 Desktop
checks, Repository Guard, and `git diff --check`. The shared Desktop and phones
were not redeployed during this isolated validation.
