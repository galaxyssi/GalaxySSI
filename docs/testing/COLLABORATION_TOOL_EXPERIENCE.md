# Saved tool experience recall

Android 1.4.137 / 1222 and Desktop 1.4.49 expose original, version-specific native
tool reuse observations through existing capability and method-history recall.

Focused verification:

- `CollaborationToolExperienceTest`: existing-record recovery, no read-time writes,
  full-read distinction, rejected requests, replays, origin/version filtering,
  resolved capability channels, blind peers, group revocation, cursor binding,
  bounded/empty-page continuation, integrity errors, workspace integration.
- `CollaborationSavedToolNativeDeviceTest`: real installed phone Python executes a
  released fixture; invalid parameters are rejected without another Python run;
  a later task reads both original outcomes through normal scoped recall. This is
  an explicitly developer-authored fixture, not autonomous learning evidence.
- Existing method experience and capability recall tests cover unchanged workflow
  and procedure history contracts.
- Desktop recall tests cover the authenticated originating-phone read route.

Verification on 2026-10-10:

- 71 focused Android JVM tests passed across tool experience, method experience,
  capability recall, evidence ledger and executable tool suites.
- Debug APK and instrumentation APK built successfully. S20U (SM-G9880) reported
  Android 1.4.137 / 1222 after the non-destructive update.
- `CollaborationSavedToolNativeDeviceTest` passed on that phone (one test,
  78.78 seconds), including native execution, rejected parameters and reopened
  history. No real model was called by this device fixture.
- 24 Desktop recall bridge tests passed with isolated temporary state.
- Repository checks passed. Broad UI, contacts, transport outage and packaged
  Desktop end-to-end suites were not rerun for this scoped read-only extension.

No new model, ranking policy, automatic adoption or quality score is introduced.
Real-model use of this history, better downstream decisions, cross-task transfer
and retained capability gains require prospective trials and are not established
by these software tests.
