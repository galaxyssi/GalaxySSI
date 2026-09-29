# Warehouse document routing regression

## Retained real-device failure

- Device: authorized SM-T575 / Active3 only.
- Android 1.3.22 (1066); Desktop 1.3.23; selected Codex model gpt-5.6-sol.
- Run: `active3-warehouse-docx-20260929`, A005 turn 0.
- Frozen catalog SHA-256:
  `945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
- Request: editable warehouse stocktaking DOCX, three sections, original data
  table, calculated total 580, unknown owner/date/benefit explicitly pending,
  native download and PNG previews converted from that actual document.
- Observation ended after 900,174 ms with parent workspace `RUNNING`, no settled
  reply and no deliverable collected. Status remains `observation_timeout`.
- Five distinct model child task IDs appeared. A completed child returned a
  phone-Linux execution plan, not a completed business deliverable. A screenshot
  showed the phone runtime step. Do not equate child completion with success.

The initial production classifier treated the Chinese warehouse term as a
software-repository scope. Combined with a creation verb, it selected supervised
phone development before the selected Desktop agent could author the document.
This is a routing defect, not evidence that the Office preview converter failed.

## Narrow repair

For Office deliverable requests, ambiguous warehouse/project scope words alone
no longer imply software development. Explicit software work (code, Python,
clone, compile, Git, APK and related terms) retains the existing route. Negative
code-delivery constraints do not count as affirmative software instructions;
negative Office requests do not suppress project routing.

The shared lexical policy feeds the requirement analyzer, task classifier and
phone-development policy. No tool permissions or execution authorization change.
Android is bumped to 1.3.24 (1067); Desktop behavior/version is unchanged.

Tests cover Chinese warehouse DOCX/XLSX, project PPTX, English project DOCX,
explicit software-plus-Office requests and negated Office requests alongside the
existing system-tool planner suite.

Final validation passed: 51 targeted Android unit tests (6 artifact-routing and
45 system-tool planner), debug APK and instrumentation APK compilation. This is
build/unit evidence, not repaired real-model artifact delivery evidence.

## Remaining acceptance

The repaired routing still needs a new real-device run of A005 and all ten
follow-ups. Do not reuse the failed run ID or turn its timeout into a pass.
Before another live run, inspect the original phone workspace and settle/cancel
only that scoped synthetic task through normal task control if it remains active.
The 100-case/1,100-turn campaign remains incomplete. No new DOCX correctness or
latency claim is made by this regression repair alone.

Private artifacts, screenshots and transcripts remain outside Git.
