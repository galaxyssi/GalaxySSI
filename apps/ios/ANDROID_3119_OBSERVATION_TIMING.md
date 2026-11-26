# Android #3119: connector observation timing metadata

Reference: Android commit `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt`, `AgentConnectorTimingPolicy`.
Scope-check baseline: `c7fe57aedc90de24c31b6e86f4b7c04db6e8e49f`.

## Implemented

- Correct interactive acceptance/running/live-stale windows from 5/8/15 to
  15/45/60 seconds. Attachment windows remain 60/90/180 seconds.
- Preserve Android stage anchors: dispatch start, transport acceptance, and
  remote status update (with acceptance fallback only when the update is absent
  or cannot be parsed). Missing, nonpositive and future anchors do not expire.
- Add informational `native_connector_observation_*` stage/start/elapsed/window
  metadata in the existing owned native connector preservation path after a
  managed query expires. Existing binding/correlation/commit guards remain.
- Only pending acceptance/queue/start or explicitly live running work can receive
  this projection. Terminal, user-input, approval and unknown statuses cannot.

## Not Implemented Or Proven

This is not a new timer: the metadata is captured when the existing managed
query expiry path runs, not necessarily at the individual timing boundary.
An already preserved observation is not continuously refreshed by this change.
No missing timestamp is synthesized. Metadata producers without the necessary
timestamps receive no timing projection.

No timeout resolver call, synthetic remote failure, retry, fallback selection,
run-slot release, network grant, new probe or retirement is added. The generic
Coordinator timeout/remote-observation pipeline and complete scored resource
router from #3119 remain incomplete. Do not treat this as #3119 completion.

Six Swift fixture methods were authored, not executed. The JavaScript check
compares source changes and frozen ownership/transport kernels only. No native
build, typecheck, XCTest, device acceptance, CI monitoring or IPA was requested
or performed for this increment.

Run the source-only scope check with:

```sh
node apps/ios/tools/check-connector-observation-timing-scope.cjs
```
