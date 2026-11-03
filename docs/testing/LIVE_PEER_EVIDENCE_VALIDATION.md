# Live Peer Evidence Validation

Date: 2026-10-09. Android 1.4.120 (1205), Desktop 1.4.43.

## Scope

This increment lets an already executing member read explicitly addressed interim
evidence from peers named in its work contract. It uses the existing publication,
recall, task identity and durable workspace paths. It does not start extra models,
change the UI, replace final-result mailboxes or grant all members a live group feed.

## Automated Results

- Android `Collaboration*` unit tests: 1,387 passed across 117 suites; no failures,
  errors or skips. Debug APK and instrumentation APK assembled successfully.
- Desktop recall bridge, retry and numeric recall tests: 40 passed.
- Desktop `npm run check`: 68 passed and the structure gate passed.
- `git diff --check`: passed.

The first broad Android run exposed a regression where checking an empty peer
journal tightened historical publication access. The fix returns the unchanged
read scope when there are no peer grants; actual grants still require current
membership. The final broad run above passed without changing those historical
acceptance tests. Recall schema expectations were extended, and publication
instructions were kept out of the read-only repair tool description.

An earlier Desktop structure check hit its existing 30-second VM timeout during
concurrent compilation. Isolated and subsequent complete checks passed; the
timeout was not increased.

## Physical Device

Only Samsung S20U (SM-G9880) was upgraded from 1.4.119 to 1.4.120. Tests used local
synthetic records, not real models, contacts, door controls or the original study.

The following classes passed together: **15 tests** in 16.837 seconds:

- `CollaborationPeerUpdatesDeviceTest`
- `CollaborationCoordinatorUpdatesDeviceTest`
- `CollaborationMilestoneDeviceTest`

Coverage includes cloud/native recall, exact original observations, unchanged
dispatch identity, independent-reader isolation, pause/resume, stopped reads,
durable milestone discovery, duplicate publication and final references.

The peer restart method was then run separately with `phase=seed`, `recover` and
`cleanup`. Seed PID 27015 and recovery PID 27056 differed. The replay page and
exact read grants survived process replacement; the original unexpanded reader
remained isolated. Cleanup completed in PID 27095. This is process-restart
validation, not a phone reboot, Doze or public-network outage test.

## Build Limitation

The local machine has no usable Cargo, so Android commands excluded
`:app:buildNativeMemory`. No native source changed. The existing packaged
`libgalaxyssi_memory_native.so` was reused and independently hashed:

`A19BC76E0A41CE6F69E83596C7F7615D23F2F4480D9C942673C4F5A21E71ACE2`

It is 3,223,568 bytes and matches the pre-build binary. Other native packaging and
embedded runtime verification ran. This is not a clean rebuild of the Rust library.

APK SHA-256:
`BC5D2311B002617C2EDBE0712D2847310EF700B14A9350B5A0AF3076AA77703B`

## Remaining Evidence

These results establish local mechanism and protocol correctness. They do not
prove that a real model chooses useful recipients, that peer evidence changes an
experiment, or that a team outperforms an equal-budget strong single Agent.
Real-model public-network delivery, causal collaboration benefit, future-task
transfer and long-term retention require separately registered trials. No new
scientific result or superintelligence claim follows from this increment.
