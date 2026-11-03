# Phase-aware collaboration publication

## Failure

Coordination and goal-assessment dispatches are deliberately not enrolled as research publications. The remote connector previously advertised the same interim-publication tool for every dispatch. A coordinator could therefore spend time preparing an artifact, receive an enrollment error, and incorrectly treat it as a repairable publication failure before starting useful work.

## Behavior

- The mandatory assignment prompt states whether the current phase can publish interim artifacts. Coordination and assessment commit their required response and assign actual production/review work; they do not gain publication authority.
- Cloud tool preparation advertises interim publication only for an eligible host-enrolled assignment. Read-only recall stays available.
- `collaboration_publish` accepts `mode=status` without caller-selected authority fields. It reports only the bound assignment, changes no workspace publication, and grants no permissions.
- A valid publish envelope in an unenrolled, candidate-transition-only or finalized assignment returns `status=unavailable`, a stable `error_code`, `retryable=false`, `artifact_validated=false` and the appropriate next action. It does not misdiagnose artifact JSON or persist a rejected artifact attempt.
- Actual enrolled artifact errors retain the existing validation/recovery path. Uncertain transport delivery still requires the same milestone ID and artifact; a status-query timeout explicitly says no artifact was submitted.
- Desktop progress distinguishes reading capability status from recording a milestone.

Desktop dynamic tools are still connector-global. This change supplies truthful assignment-scoped capability discovery and enforcement; it does not claim per-thread dynamic-tool hiding on Desktop.

## Verification

Unit coverage includes enrollment transitions, no-write capability reads, cross-assignment isolation, final publication, candidate transitions, access removal, malformed authority fields, all research prompt stages and oversized context. Protocol tests cover authenticated status envelopes and unchanged uncertain-publication retry behavior.

The dedicated device test uses a temporary encrypted group and no provider calls. It checks reopen, unenrolled rejection, no false checkpoint, all cloud provider tool lists, and an enrolled member's successful publication. Existing milestone scheduling, retries and versioning tests remain in the regression suite.

This is a reliability and decision-feedback change, not evidence of learning, scientific novelty, multi-agent superiority, or improved real-model task completion. Private research inputs and records are not included in this repository.

## Verified build

- Android 1.4.92 (1177): broad regression 1391 tests / 114 suites passed; final prompt/capability refinement 71 targeted tests / 7 suites passed.
- S26U: all 7 `CollaborationMilestoneDeviceTest` tests passed after an in-place install; no model invocation.
- Desktop 1.4.26: 83 backend tests and all 68 `npm run check` tests passed. The first structure check timed out under concurrent Android compilation; the unchanged command passed after compilation without raising its timeout.
- APK SHA-256: `e3d0a25e7d0381ae3f537b3dfbc07f577f101d19347fb44d0564a3b0ed052320`.
- Desktop was restarted, its main page showed 1.4.26, all three MQTT paths were receive-ready, and no model tasks remained active or pending.
