# Candidate Publication Retirement

## Scope

Android 1.4.32 (1117) adds a durable publication fence to the explicit completed,
unpublished documentary-review reassignment introduced in 1.4.31. It does not
change the user goal, UI, concurrency limits, evidence requirements, or permissions.

The persisted team graph is still committed before dispatch. At the real worker's
publication enrollment, the workspace commits the new host contract and retirement
of the predecessor in one encrypted transaction. This is not a distributed
transaction between the team store, workspace, provider, and Desktop.

- Old publication first: preserve it and refuse the replacement claim.
- Replacement claim first: reject all later publication by the old node, including
  native repair submissions and generic publication without candidate metadata.
- Late raw replies remain in the old journal as rejected, retired audit attempts;
  they cannot become new workspace objects. Identical redelivery is deduplicated.
- The old host outcome, original sources and candidate remain intact.
- Repeated enrollment by the same exact owner is idempotent; competing successors,
  altered scope/contracts, missing/corrupt records and revoked access fail closed.
- An interrupted storage transaction cannot leave retirement without enrollment.
  If the process exits after both commit, the successor reuses its saved contract.
- Retired candidate replay and publication repair stop with an explicit reason;
  the old response is not treated as a draft that should consume further retries.
- Later repair/recheck tasks use independent dispatch identities. Retirement of
  their predecessor remains durable without making descendants compete for its claim.

Lookup is by exact dispatch key, without a workspace scan, model call or MQTT
control message. The shared workspace lock serializes claims and publications.

## Verification

`CollaborationPublicationRetirementTest` covers atomic failure, idempotent reopen,
both ordering outcomes, concurrent publication/claim races, old reply audit and
duplicate suppression, competing owners, retirement chains, missing/tampered
contracts, membership revocation, scope mismatch and recovery-loop termination.
Existing collaboration and MQTT suites remain part of the regression selection.

`CollaborationPublicationRetirementDeviceTest` uses isolated encrypted fixture
databases. Run its `retiredWriterRemainsFencedAcrossRealProcessReplacement` method
first with `-e retirementPhase seed`, then in another instrumentation process with
`-e retirementPhase recover`. Recovery asserts different process IDs, refuses the
old writer, preserves its raw audit, publishes through the successor, replays the
saved receipt and removes only the fixture data. No model, contact, physical tool
or original user research is invoked.

## Remaining Acceptance

This is a host-workspace publication fence, not general provider cancellation,
distributed lease ownership or offline side-effect replay. Eligibility still
requires an already host-completed unpublished documentary review. Unknown,
running, failed or user-stopped executions cannot be replaced through this path.
Full offline member handoff needs authoritative execution reconciliation and
remote-side fencing, as well as real-provider and outage acceptance. Scientific
validity and equal-budget team improvement remain separate evaluation goals.

## Results: 2026-10-03

- Both application and instrumentation APKs compiled. Source and APK metadata
  identify Android **1.4.32 (1117)**.
- Final regression: **784 JVM tests in 61 suites**, zero failures, errors or
  skips (`Collaboration*` and `Mqtt*`). This includes 11 new cases, with 12
  concurrent old-publication/handoff interleavings inside the race case.
- The initial run found an existing fixture bypassing production publication
  enrollment. The fixture now follows the real boundary; no guard was weakened.
  The final frozen-source build also includes nonconsecutive duplicate-audit
  suppression and the reassignment-to-repair/recheck continuation test.
- Kotlin source size policy and `git diff --check` passed. Repository-wide
  checks were not rerun; existing Android deprecation warnings remain.
- S26U disconnected from ADB during compilation. Installation returned
  `device not found`, and `adb devices -l` then listed no devices. Therefore this
  version has **not yet been installed or device-verified**; the prior verified
  S26U version remains 1.4.31. The new separate-process device test is implemented
  but not counted as passed.
- Desktop was not changed/restarted. No paid provider, original research,
  contact message, physical tool or other device was used.
