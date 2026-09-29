# Image grading: item coverage and resumed execution policy

## Scope and frozen workload

The artifact campaign remains 100 cases and 1,100 turns. This record covers
A044, synthetic handwritten arithmetic, on the explicitly selected Active3
SM-T575 with Android 1.3.22 and configured Codex gpt-5.6-sol. It is not acceptance
of real human handwriting recognition or the complete business campaign.

Catalog SHA-256:
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
Preserved phone input `A044-input-0.png`, 1200 x 1600, SHA-256:
`ea554955c52210a01c69f43bf7dd71f5fc67e7e34d070033f5c5d0523ee8facc`.
The private scoring oracle is not included in the model request. Prompts,
fixtures, model selection and latency target are unchanged between runs.

## Baseline, Desktop 1.3.22

Run `active3-handwriting-20260929-preserved` completed all eleven turns.

| Turn | Requested change | Reply terminal ms | Visible content review |
| --- | --- | ---: | --- |
| 0 | Initial annotation | 130121 | FAIL: omitted first incorrect answer |
| 1 | Minimal marks | 58950 | First correction still absent |
| 2 | Dark red ink | 60774 | First correction still absent |
| 3 | Handwriting-style marks | 118418 | First correction still absent |
| 4 | Distinguish unreadable answer | 91925 | Uncertainty explicit; first correction absent |
| 5 | Undo third-row mark only | 62674 | Third mark removed; missing first mark persists |
| 6 | Restore third-row mark | 68204 | Third mark restored; missing first mark persists |
| 7 | Text-only summary | 31503 | Correctly identifies both errors and unreadable answer |
| 8 | Verify against original | 74116 | Both corrections finally present |
| 9 | Improve legibility | 63989 | Both corrections and uncertainty note retained |
| 10 | Final single image | 53598 | Same correct content, single current image |

All ten image turns delivered one 1200 x 1600 PNG. Containers, version names,
download/save hashes and all eleven stopped timers passed; all eleven target
reply captures were focused and stable. Turn 7 returned text without a file.
Background turns 2, 5 and 8 passed their immediate capture checks in this run.
Every exported image was visually reviewed. Correct rows remain unmarked;
original questions and answers are readable. This is not a pixel-identical
original claim: comparing the phone fixture with returned images finds changes
in original ink pixels, so preservation of visible content and byte-level
preservation must not be conflated.

The first image misses `12 + 7 = 18`, although it corrects `40 - 16 = 26` to 24.
The text summary later recognizes 19 and the next image adds it. That later
recovery does not turn earlier missed corrections into successful grades.
All reply observations were within the unchanged 180-second target, but eleven
samples do not establish a stable p95 or an improvement in model accuracy.

## Production change, Desktop 1.3.23

- Require separate observations for every question, its written answer and an
  independently computed answer; uncertainty must not be inferred away.
- Require reconciliation of every readable item, including those first judged
  correct, and inspection of the actual exported image before delivery.
- Preserve single-image and text-only requests; no extra answer card is added.
- Supply the current developer instructions on both ordinary thread resume
  and persisted-task recovery, not only when creating a thread. Keep history
  and the already-loaded-thread fast path; do not reset conversations.

These are generic execution instructions, not hardcoded fixture answers and
not a deterministic correctness guarantee. Official app-server documentation
describes [configuration overrides on resume](https://learn.chatgpt.com/docs/app-server).
The installed app-server JSON schema also exposes
`ThreadResumeParams.developerInstructions` as string or null.

59 isolated backend tests pass across conversation threads, response checks,
image fidelity, startup concurrency and MQTT recovery. Assertions cover current
instructions on start, prewarm/resume and recovery; repeat prewarm still avoids
an unnecessary resume call.

All 18 catalog/report tests and 61 Desktop JavaScript unit tests also pass.
The subsequent `npm run check` static contract fails on an existing main-branch
assertion: `check.js` expects only `web_source_sites.tsv` in `backendDataEntries`,
while `package-win.js` also includes `research_contract`. Both files are
unchanged against main commit `c7256632f`; this patch does not claim the entire
Desktop check passes or alter that unrelated packaging contract.

## Fresh real-device validation

Run `active3-handwriting-20260929-desktop1323` uses the same frozen input and
prompts. Its first turn completed in 92,548 ms and delivered one 1200 x 1600
JPEG with matching save/download hash. The first and third incorrect answers
are both corrected, correct rows remain unmarked, and the obscured answer has
an orange question-mark annotation. The uncertainty wording is not yet as
explicit as the later follow-up requires. Its focused stable capture and stopped
timer checks pass.

The same run then completed all eleven turns without changing its prompts:

| Turn | Reply terminal ms | Review |
| --- | ---: | --- |
| 0 | 92548 | Both errors corrected; question mark for obscured original |
| 1 | 70255 | Circles removed, both corrections retained |
| 2 | 55926 | Dark red marks; received in background |
| 3 | 81079 | Clear handwriting-style corrections |
| 4 | 123800 | Explicit unreadable/pending label separate from computed answer |
| 5 | 76073 | Only third-row annotation removed; first correction retained |
| 6 | 75872 | Third-row mark restored after reopening the conversation window |
| 7 | 36378 | Correct Chinese summary, no attachment |
| 8 | 86648 | Both corrections and uncertainty retained; background receipt |
| 9 | 95291 | Thicker readable marks; immediate target-row capture failed |
| 10 | 88891 | Exactly one current final image |

All ten image turns return one 1200 x 1600 JPEG with passing container and
save/download hash checks. All eleven timers stopped. All exported images were
visually inspected: original question/answer content remains visible, correct
rows are unmarked, and no extra answer card is returned. This remains visual
content evidence, not a byte-identical original claim or real handwriting score.

The immediate turn-9 capture had focus and loaded text but could not find its
recorded entry ID. Its subsequent process screenshot already shows the correct
thumbnail. A separate read-only reopening of that same turn then passed focused
stable capture, thumbnail click, fullscreen opening and Save. The new download
hash matches `51b345c8fdd183c84006cfbcab2f9fff41ae357e297d48a26a7035620ea61ef0`.
The later audit resolves a different assistant entry ID for the same turn/text,
so stale row identity is an investigation lead. Do not overwrite the original
failed observation or claim the capture/restoration race is fixed by this patch.

Reply p50 is 81,079 ms, versus baseline 63,989 ms; all are within 180 seconds,
but this is not a speedup. p95 is unreported with only eleven samples. Boundary
PSS samples range from 367,794 to 451,652 KiB, not a continuously measured peak.
USB-powered battery observations cannot establish energy consumption.

## Remaining acceptance

- Resolve the stale-entry/immediate-capture failure without weakening target
  identity checks or replacing old failed evidence with later captures.
- Repeat across independent images and real handwriting before claiming general
  grading reliability. This fixture contains only synthetic digit strokes.
- Execute and review the rest of the 100-case campaign; delivery checks alone
  must never be reported as semantic success.

Private transcripts, screenshots, originals and generated artifacts stay out of Git.
