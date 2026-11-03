# Research deliverable selection

Desktop v1.4.50. Android UI and model selection are unchanged.

## Problem

A valid `galaxyssi.research-artifact.v1` final response may only reference already
published milestones. The ordinary unlinked-reply fallback treated every file in
its bounded output inventory as a deliverable. Internal scripts, intermediate
measurements and older checkpoints could therefore be attached alongside a final
archive. File modification time is not a reliable version selection rule.

## Contract

- Parse the complete JSON envelope, including an optional JSON code fence.
- Only local Markdown links in its public `summary` select phone files. Links in
  workspace bodies are evidence, not download requests. Resolve explicit links
  beyond the first 50 inventory files through the existing confined resolver.
- No local summary links means no file attachments. An invalid or missing link
  never falls back to a different archive or the entire directory.
- Required downloadable outputs remain required. Missing declared local files
  produce failed artifact verification, including their relative paths. Archive
  integrity checks still apply. Structured publications are not auto-packaged.
- Keep research workspaces on Desktop both after text-only completion and after
  file acknowledgement. The immutable peer handoff mechanism remains unchanged;
  this is not a new cross-Desktop transport or a scientific acceptance rule.
- Preserve the exact JSON response through first delivery and result replay.
  Retention also applies to legacy fallback re-publication.
- Ordinary Markdown/chat/image/Office output selection keeps existing behavior.

Publication, text-handoff and file-handoff tool descriptions advertise this
contract before execution. Models choose intended versions explicitly; neither
the newest timestamp nor network arrival order makes a candidate the final one.
This does not select the scientifically best candidate or change App goal status.

## Verification

`test_research_delivery` exercises 14 cases including 60 intermediate files,
an older checkpoint with a newer timestamp, missing files, exact summary-only
selection, task-store reopen, the real final callback with isolated transport,
Blob batch retention through acknowledgement, and fallback replay.

The wider Python regression command covers 179 tests (177 passed, two symbolic
link capability tests skipped on this Windows host). Desktop's 68 JavaScript
tests and the structure check passed. An initial JavaScript run hit the existing
30-second structure-check timeout; the unchanged retry and direct check passed.

No real model calls, phone operations or production Desktop restart were used
for these checks. A live multi-member delivery acceptance run remains necessary.
Private experiment records and paper artifacts are not part of this change.
