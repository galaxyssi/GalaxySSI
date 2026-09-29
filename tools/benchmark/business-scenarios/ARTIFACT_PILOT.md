# Artifact Pilot: Active3

Device: Samsung Galaxy Tab Active3 (SM-T575). Only this device was operated in
this extension. Data is synthetic; no private documents or diagnostics are committed.

## Scope

- 100 planned scenarios across 25 domains and four deliverable families.
- Eleven turns per scenario: initial request plus ten follow-ups.
- Ten image scenarios cover original-image correction, annotations, synthetic
  handwriting, image summaries, selective undo/restore and two-image comparison.
- Office originals must remain editable; phone previews must be rendered from
  those originals. A plausible-looking separate image is not preview verification.
- Delivery, content accuracy, preview fidelity and actual UI interaction are
  distinct checks. A completed model task is not a successful end-to-end task.

## Historical Observations

| Run suffix | Case | Result |
| --- | --- | --- |
| `v1-20260929-r1` | A001 Word | 300-second timeout. A negative code-output constraint and a quoted business field incorrectly triggered phone development. A044 was not reached. |
| `v1-20260929-r2` | A001 Word | Desktop completed in about 238 seconds and reported a DOCX; phone still waited at 300 seconds. No Office preview was delivered. File contents and download were not verified. |
| `v1-20260929-image1` | A044 annotation | Desktop completed in about 56 seconds; phone still waited at 300 seconds. No final image was inspected. A later recovery attempt produced an error, not the artifact. |
| `v1-20260929-image2` | A044 annotation | Phone completed in 88,913 ms. One 1200 x 1600 JPEG was received; the normal Downloads API saved it and read-back SHA-256 matched. Stable screenshot and stopped timer passed. |

The last row is **not a content-quality pass**. Visual inspection found correct
corrections for rows 1 and 3, unchanged correct answers for rows 2 and 4, but an
incorrect wrong-answer mark on the unreadable fifth answer. Its screenshot also
showed a file card rather than the expected thumbnail after the file arrived.
Tapping/enlarging and the actual save button were not verified in that run.

The original image-edit oracle required PNG even though its prompt did not.
That format failure was a test defect, not a model failure. Catalog revision 2
accepts PNG/JPEG for unspecified image output and checks original dimensions.
Historical catalog snapshots and reports are not rewritten or relabelled.

## Post-Repair Image Checkpoint

Run `active3-artifacts-v2-20260929-image1`, Android v1.3.19 (1063), Desktop
v1.3.15, real Codex `gpt-5.6-sol`. The frozen revision-2 catalog SHA-256 is
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.

Both A044 turns completed: 76,567 ms for original annotation and 63,757 ms for
the requested smaller marks. Each returned one 1200 x 1600 image. Downloads
save/read-back hashes matched; focused screenshots were stable, both timers
stopped, and visual inspection confirmed inline thumbnails instead of file cards.
This verifies two ordinary foreground delivery samples, not weak-network p95.

Neither image is a content-quality pass. Both omit the correction of row 1
(`12 + 7 = 18`) and put `23` beside the obscured fifth answer without marking
the original answer as unreadable. Row 3 is corrected to `24`; the second turn
makes the marks smaller and retains the original. Prompt policy alone did not
eliminate model mistakes. The first turn also lost its version prefix in the
user-facing/download name even though its source URI contains `ART-044-v01`;
the strict filename assertion failed. The second passed delivery assertions.
The image container is compressed during transport; a `.png` label is not proof
of PNG bytes. Actual UI tapping/enlarging and save-button behavior remain unverified.

## Post-Repair Office Checkpoint

Run `active3-artifacts-v2-20260929-office1` uses the same app, Desktop and frozen
catalog as the image checkpoint. A001 Word completed in 167,004 ms and delivered
an editable DOCX with matching Downloads read-back hash and a stopped timer.
Read-only OOXML inspection found three sections, real tables, record `ART-001`,
line amounts 132/168/160 and total 460; missing owner/date/revenue were marked
pending confirmation. No actual Office-rendered preview arrived. The model
reported a missing converter; that statement is not a verified inventory of all
host applications. Layout fidelity and full preview acceptance therefore fail.

A002 Excel returned a terminal failure after 272,492 ms: its PowerShell preview
export command failed and the recovery budget stopped the model. The phone
displayed the failure and stopped its timer, but no XLSX or preview was delivered.
A003 PowerPoint exceeded the 360,154 ms phone observation window. Desktop later
completed after 488,790 ms with a PPTX and four PNGs, using PowerPoint SaveAs and
Export on the actual presentation. All four local previews were visually inspected:
readable Chinese, four distinct slides, amounts 156/184/180 and total 520, no
obvious overlap. This is late Desktop artifact evidence, not verified phone
delivery/save, and does not erase the timeout. A scoped stop request found the
task already completed; no user task was cancelled.

The live Office run preceded the final Desktop-only routing/finalization patch.
That patch ignores negated code/research mentions and quoted business keys,
recognizes explicit Office creation, and keeps native Office outputs plus previews
separate unless an archive is requested. Its contract asks the model to check
installed converters rather than assuming LibreOffice is the only option.
These changes have unit coverage, not a new successful Office live run.

## Repairs and Validation

1. Exclude negated code-delivery instructions and quoted business fields from
   phone-development routing, while retaining affirmative programming requests.
2. Persist authenticated final replies before Activity presentation can acknowledge
   the transport envelope. Previously a foreground reply could be acknowledged
   while its durable write was still waiting on the Activity recovery executor.
3. Invalidate only the stable transcript row whose artifact has arrived; ordinary
   text updates and unrelated rows retain their views.
4. Require image review to distinguish recognized original text, calculated
   answers and grading judgments. Unreadable answers are unknown, not wrong.
5. Keep artifact delivery assertions separate from content-quality assertions;
   an error message cannot satisfy artifact recovery acceptance.

Validation for this extension: 32 targeted Android JVM tests, 11 host
catalog/report tests, 97 Desktop routing/harness/Codex/policy tests, and 13 Active3 device
regressions passed. Main and instrumentation APKs built and installed in place.
Desktop `npm run check` passed its 61 Node tests but its final existing backend
auto-discovery contract check failed on `web_source_sites.tsv`; the full command
is not green. Device regressions cover durable ingress, identity rejection,
idempotence, result recovery and targeted stable-row invalidation.

These repairs do not establish that every earlier timeout had the same cause.
The 100-case / 1,100-turn real-model campaign remains incomplete. Long-form
Office conversion, true human handwriting, ten-turn artifact revisions, and
full UI open/save acceptance still require further real-device evidence.
