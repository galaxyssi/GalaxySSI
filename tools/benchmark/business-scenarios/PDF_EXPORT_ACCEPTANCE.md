# PDF export delivery contract

## Real failure retained

Active3 run `active3-warehouse-docx-20260929-v1324`, A005 turn 9, requested a
downloadable PDF with PNG previews while retaining the original format. Its
frozen acceptance requires DOCX, PDF and previews. The Desktop task
`b1b73222-a88b-3b35-a085-231b50775b34` completed with three PNG pages and a PDF,
but no DOCX in its published `output_files`. The phone received all four
declared files; this is a missing deliverable, not evidence that MQTT lost a
declared Word file. The failed original observation is retained.

The persisted execution policy classified this request as `research`, with
`requires_artifact=false`, despite file intent. PDF creation/export was not
recognized by the bounded Office-request matcher, and the fallback artifact
terms did not cover this wording. Consequently the execution contract omitted
its mandatory artifact-delivery instructions. This explains an actual policy
gap, not a proof that correcting instructions alone guarantees model compliance.

## Change

Desktop 1.3.24 recognizes affirmative Chinese/English PDF creation, conversion
and export requests as artifact tasks. Local negations and English word
boundaries remain enforced. Screen analysis and plan-only requests retain
their read-only behavior.

The artifact execution contract now distinguishes retained editable originals
from explicit PDF-only/preview-only delivery. It requires reconciliation of
requested formats with actual files and final attachment links, and reporting
missing deliverables instead of claiming complete delivery. It does not copy
arbitrary prior documents, broaden filesystem access, invent missing files or
relax artifact validation. Android production code is unchanged.

## Verification and limitations

- 106 isolated backend tests pass across artifact request policy, execution
  harness, Office preview/worker and Codex conversation continuation.
- 61 Desktop JavaScript tests pass.
- `npm run check` still fails at an existing packaging assertion that expects
  only `web_source_sites.tsv`, while main already also packages
  `research_contract`. This patch does not change or disable that assertion.
- The running Desktop instance has not been replaced: the execution environment
  rejected the restart command. No repaired real-model PDF export is claimed.
  A manual Desktop exit was requested before launching the new version.

Next: deploy this version and run the unchanged real multi-turn export scenario
on Active3. Verify the editable source, PDF and previews as separate delivered
files, inspect their contents, and retain the existing failure. The broader
100-case / 1,100-turn campaign and intermittent preview delivery delay remain
unfinished.
