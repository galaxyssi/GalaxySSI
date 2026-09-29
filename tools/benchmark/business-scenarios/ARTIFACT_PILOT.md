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

### Office Renderer Follow-Up

Desktop v1.3.16 adds the task-scoped `galaxyssi_office_preview` dynamic tool.
It converts the saved Office original to PDF and PNG through an installed
LibreOffice or Windows Microsoft Office renderer, and reports source hashes,
page coverage and failures to the model. It does not reconstruct a look-alike
preview from extracted text. Poppler must be available on PATH. No dependency
is silently installed. Only one Office conversion runs at a time; existing
interactive Windows Office processes cause a busy failure rather than takeover.
Macros, embedded active content, external resources and ambiguous ZIP entries
are rejected before conversion. This is input hardening, not a sandbox for
arbitrary hostile documents.

A real previously generated DOCX rendered into two readable pages with its
original hash unchanged. A native Excel fixture also rendered; the earlier
model-generated XLSX was rejected by Excel itself. These component checks are
not business quality passes, and the LibreOffice branch remains unverified on
a real installation.

The Active3 run `active3-artifacts-v2-20260929-word11` then returned real Word
page previews. Its first two turns completed in 270,828 and 229,281 ms, but
neither delivered the DOCX card. Desktop retained the original in `output_files`:
the rich-output builder selected artifacts again after visible-text cleanup
had removed the original's local link. The repair selects from raw model output
while displaying sanitized text, for both normal delivery and result replay.
DOCX/XLSX/PPTX-plus-preview regression cases preserve both intended artifacts
and still exclude an unlinked draft. The running device campaign predates that
repair's deployment and must not be described as a verified delivery fix.

The third turn hit the 360-second observation timeout after an unisolated host
test imported the default task manager while Desktop was running. Desktop logs
recorded task storage revision conflicts and the task changed to restart
recovery despite the Desktop process not restarting. This is a contaminated
test run, not evidence of a model-quality failure. The checkpoint was retained;
Desktop was subsequently restarted with only that synthetic task active. Its
existing recovery path stopped it as failed after repeated recovery attempts;
it was not resubmitted under the same test identity. Future host regressions
use `tools/dev/test-run-kernel.py` to isolate state before module imports.

Run `active3-artifacts-v2-20260929-word-delivery-fix` then completed A001 in
229,748 ms on Android v1.3.19 and the repaired Desktop v1.3.16. The phone received
the native DOCX and two page images, with a stopped timer and stable capture.
The screenshot shows the DOCX download card and inline preview. OOXML inspection
confirmed editable paragraphs/tables, three sections, amounts 132/168/160 and
total 460, with missing fields marked pending.

Its strict report remains failed: preview labels lose the requested version
prefix, and save read-back selected earlier files because `saveToDownloads`
returned the requested filename instead of the name assigned by Android after
a collision. The actual files named `... (1).docx` and `... (2).jpg` were inspected
separately; all three download hashes match the received originals. Android
v1.3.20 reads the assigned display name from the returned MediaStore URI, with a
dedicated two-save regression. This does not rewrite the older report or prove
full UI-button, ten-follow-up, or 100-case acceptance.

The Office/rich-output follow-up passed 201 isolated Desktop Python regressions
and 11 host catalog/report tests. Expected mocked failure logs are not live
task failures; tests must not use the user's state directories.
Android v1.3.20 (1064) app and instrumentation APKs compiled and were installed
in place on Active3. All three `AgentDesktopArtifactStoreTest` device tests
passed, including repeated-save actual filenames, separate download identities,
read-back hashes, chunk reassembly and rejection of mismatched artifact versions.

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
### Office retry and presentation follow-up

Run `active3-artifacts-v2-20260929-office2` used Active3 v1.3.20 and Desktop
v1.3.16, with a 600-second observation window and two turns per Office case.
The instrumentation driver ended normally, but none of its four turns passed
the strict business acceptance checks:

- A002 create returned a terminal failure in 221,733 ms with no file. Missing
  Python libraries and a Windows PowerShell script-encoding error consumed the
  outer replan budget even though they were different failures.
- A002 revise completed in 376,206 ms, delivering the XLSX plus three actual
  Excel previews. All four saved download hashes match. The visible calculation
  preview contains quantities 12/29/17, amounts 144/232/170 and total 546;
  chart title/value overlap remains a layout defect. Preview download names lost
  the requested version prefix, so the strict delivery result remains failed.
- A003 create completed in 530,374 ms with the PPTX and four previews received.
  The task timer stopped. Full content/fidelity and UI-button acceptance have
  not been established; the strict filename check failed.
- A003 revise returned `Requested phone attachment is unavailable` in 36,595 ms,
  with no artifact. Its capture shows the preceding reply, not the current turn;
  the false timer result does not prove that a running timer remained on screen.
  This continuation recovery defect is still open; do not count the terminal
  error as success.

Desktop v1.3.17 preserves original image download filenames separately from
friendly captions, omits raw command paths/bodies from both public progress
formats, and lets Codex handle a first native command failure in the same turn.
The native failure fingerprint includes the observed error, duplicate item
events count once, and repeated identical failures still stop the task. Durable
failure counts, no-progress watchdogs and other replan limits remain enabled.
These changes passed 176 isolated Desktop regressions. Their real-model rerun
is pending; the older observations above are not relabeled as repaired passes.
Image-review guidance also requires source-region grounding and reopening the
actual output to check corrections, retained content, uncertainty and undo state;
this is not proof of improved grading accuracy.

### Delivered-Output Recovery and Capture Audit

The failing PPT continuation explicitly requested the preceding assistant's PPTX
artifact ID. Android's old recovery lookup only searched user-input manifests.
The preceding Desktop task still has output metadata, but its original workspace
file no longer exists; local Desktop lookup alone cannot repair this case.

Android v1.3.21 (1065) adds an on-demand lookup of assistant artifact blocks in the
same conversation, including older transcript pages. It accepts only locally
delivered, version-matched artifact records and verifies actual size and SHA-256
before offering the content URI for the existing authenticated transfer. It does
not fetch arbitrary links or borrow files from another conversation. Desktop
v1.3.18 first restores a retained, hash-matching output from the same authenticated
conversation/turn, then requests any remaining IDs from the phone. Both paths
bound their scan/hash work; ordinary chat does not perform these recovery scans.

The application and instrumentation APKs compiled and were installed in place
on Active3. Five artifact-store device tests passed, including cross-page output
recovery, original filename retention, cross-conversation rejection, user-input
rejection and mismatched versions. The Desktop repair passed 200 isolated
regressions, including nine local recovery cases. These component results do not
establish a successful real-model PPT revision. The Desktop source changes have
not yet been loaded in the running process.

Driver schema 3 separately targets the exact final reply and the same turn's
process row. A loaded view model no longer proves visible rendering. Captures
check the attached RecyclerView holder identity and visible bounds; process
timing has its own screenshot. Re-captures are separate timestamped audit files,
not rewrites of the original run or its model/latency results.

The A003 two-turn recapture passed on Active3. The second turn's exact error row
is now visible; its separate process capture reads "processed 34 seconds".
The first turn's process row was not captured, so its timer is still unobserved
in this audit. Neither capture changes the failed artifact result. Twelve host
catalog/report tests pass, including rejection of legacy view-model-only evidence
as verified current-reply visibility.

The 100-case / 1,100-turn real-model campaign remains incomplete. Long-form
Office conversion, true human handwriting, ten-turn artifact revisions, and
full UI open/save acceptance still require further real-device evidence.

### Active3 Phone-Recovery Probe

Run `active3-artifacts-v2-20260929-phone-recovery` used Android v1.3.21 and the
still-running Desktop v1.3.16. A003 creation failed after 256,759 ms on Desktop's
old repeated-command rule. Its second turn completed in 315,670 ms and delivered
a 53,709-byte editable PPTX and four 1600 x 900 previews. All five Downloads
read-back hashes match. OOXML text and the data-page preview show quantities
13/30/18, amounts 156/240/180, quantity total 61 and amount total 576. The initial
turn never delivered a native file, so this is not proof of revising a previously
delivered PPTX. Both strict business results remain failed; the second retains
the old Desktop preview-name defect. Full content and preview-fidelity approval
is not claimed from checking a single data page.

Driver schema 3 captured both actual final replies and both stopped process
timers. The failed first reply nevertheless exposed the raw command through the
terminal error field, despite progress sanitization in newer source. Desktop
v1.3.19 returns the concise stopped/repeated-failure explanation in that field
instead of command/output details. Eighty-one isolated Codex/harness regressions
pass, including terminal-event privacy and preserved failure termination.

The existing Agent image and gallery thumbnails use center-crop, which cuts off
the sides of a 16:9 page in the fixed thumbnail frame. Android v1.3.22 changes
only their image scale mode to fit-center. Frame dimensions, filenames, source
bytes, enlargement and save behavior are unchanged. The app/test APKs compiled
and were installed on Active3. Seven device tests pass: rendered screenshot
pixels retain all four colored markers on landscape, portrait, square and gallery
images; the five artifact integrity/save/recovery regressions also pass.

Real-PPT recapture first failed because the prior turn was outside the initial
history page. The audit now uses the existing load-older-message UI path before
looking for its exact row. The rerun captured both real replies successfully;
visual inspection confirms the visible PPT previews retain their full page
width. It does not claim that all pages fit on one phone screen or that the
older filename/failure-recovery business defects have passed.

### Real Preview Open and Save

An opt-in audit reopens one explicit completed turn without sending another
model request. It locates the delivered image in that exact transcript row,
clicks its actual thumbnail, checks the fullscreen image and save control, and
clicks Save. Only newly created GalaxySSI Download rows are candidates for the
SHA-256 read-back comparison. The audit requires an explicit valid turn index
and fails if no completed turn was exercised.

On Active3 v1.3.22, the first real PPT preview from the phone-recovery run passed
this UI flow. Visual inspection of the fullscreen capture confirms the full
landscape page, Chinese title, quantity total 61 and amount total 576 are visible.
The new saved image matches the received image byte-for-byte. This is one actual
preview open/save acceptance, not proof of all four pages, external Office-app
opening, prior-PPT revision recovery, or the full 100-case campaign. Test evidence
and screenshots remain local; no private artifacts are added to the repository.
The rebuilt instrumentation repeated the positive flow successfully in 8.483
seconds. An intentional out-of-range index (999) was rejected before opening a
conversation; this negative probe is expected failure evidence, not a model run.
