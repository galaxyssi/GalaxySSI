# Collaboration workspace result contract

## Problem

Desktop's ordinary build policy requires a local downloadable artifact. An internal
collaboration assignment can mention implementation, tests or another node's
`build` identifier while delivering immutable workspace records instead. Reapplying
the build-file rule after publication made members manufacture duplicate JSON
handoff files, including for independent reviews.

## Ownership

Android marks managed collaboration-group assignments with
`result_contract=galaxyssi.collaboration-workspace.v1`. The marker is not inferred
from prompt text. The Android sender requires a managed action and validated team
and member identities. Ordinary tasks and non-collaboration teams retain their
existing behavior. Unknown contracts fall back to ordinary delivery.

Desktop preserves this contract in its execution policy and unstarted-request
snapshot. Build keywords alone no longer require a local file for such assignments.
Explicit file creation/export/image/video and installation requirements still use
the existing artifact checks. Plan-only and screen-analysis restrictions take
precedence. This contract adds no tool, resource or filesystem authority.

Artifact finalization uses the admitted policy rather than inferring a second policy
from task text. This applies to the MQTT finalizer and the remote Agent gateway.
Members publish originals once, exchange exact version references and read originals
for review. Local files remain appropriate when explicitly requested, not as a
mandatory duplicate of already published records.

App publication validation, original-evidence checks, independent release/review,
goal coverage and final-delivery acceptance are unchanged. A Desktop task finishing
without an output file is not evidence that the App accepted the collaboration goal.

## Regression checks

- Implementation, review and reuse assignments do not require duplicate files.
- Ordinary build tasks still require their deliverables.
- Word, Excel, PowerPoint, PDF, image, video, downloadable JSON and APK requests
  retain artifact requirements.
- Read-only and plan-only tasks do not gain publication authority.
- Unknown markers and markers embedded in user text cannot change the policy.
- Stored policy and unstarted-request recovery retain the selected contract.
- Finalization does not recreate the old inferred build-file requirement.

These checks concern result ownership, not learning gains or scientific novelty.
