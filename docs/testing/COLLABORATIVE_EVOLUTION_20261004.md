# Collaborative Evolution Verification

Date: 2026-10-04

## Build

- Android v1.4.40, versionCode 1125.
- Desktop package v1.4.8; the running Desktop instance was not restarted in this verification.
- Android debug APK and instrumentation APK built successfully.
- Existing native memory output was reused (`-x :app:buildNativeMemory`); embedded runtime requirement disabled for this debug build.
- Kotlin source-size policy and whitespace checks passed.

## Automated Results

- 652 collaboration unit tests in 51 suites: zero failures, errors or skips.
- 14 Desktop collaboration recall bridge tests: passed.
- S26U (SM-S9480), only device used for this change: four instrumentation tests passed.
- `CollaborationEvolutionDeviceTest`: two new synthetic cases, 0.889 seconds reported by JUnit.
- Existing encrypted workspace and scoped cloud/native recall regression: two cases, 0.766 seconds reported by JUnit.
- Device package query confirmed versionName 1.4.40 and versionCode 1125 after replacement install.

The first unit run exposed a stale recall-mode expectation and a fixture that reused a publication
dispatch while trying to test self-review. Both were corrected; the final full run passed.

## What Was Proven

- Typed innovation records and experiment plans/results survive encrypted store recreation.
- Scoped directories preserve blind current-round isolation and allow later authorized group tasks to recall lessons.
- Measured comparisons are recomputed from original tool-report fields, not model-authored summary scores.
- Source/time/version/environment/budget mismatch, duplicates, missing samples, non-finite values and regressions cannot earn retention.
- Retention requires a distinct reviewer and original evidence-page coverage.
- Old target results and negative experience remain durable, but cannot approve a newer target revision.
- Original baselines, contributor lineage, immutable plans and historical revisions remain available.
- Fixtures were cleaned up; no user conversation was deleted or original research restarted by the test.

## Not Proven

- No real Codex/DeepSeek research or external tools were invoked by these fixtures.
- No real innovation superiority, statistical significance, scientific validation or new physical experiment was demonstrated.
- No live MQTT round trip with the updated Desktop bridge was run.
- No new multi-day Doze/network/reboot campaign was run; existing durable workspace/control mechanisms are reused.
- Retained procedures are scoped learning candidates, not automatically installed Skills or deployed tools.

Next product evaluation should compare a baseline single Agent and the collaboration team at the
same total budget on held-out tasks, inspect novelty and factual correctness independently, and
include failed transfer, regression, recovery and cost measurements.
