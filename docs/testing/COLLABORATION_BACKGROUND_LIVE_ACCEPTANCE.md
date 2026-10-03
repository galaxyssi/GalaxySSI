# Background live collaboration acceptance

The opt-in `CollaborationLiveEvidenceDeviceTest` can now run without launching
an Android activity. This removes a UI-only dependency from provider/runtime
acceptance; it does not bypass a secure lock screen or grant more permissions.
The UI fixture remains available separately.

## Invocation

Only run on the explicitly authorized test phone, with authorization for actual
Codex and DeepSeek requests and an already paired Desktop:

```text
adb -s <authorized-serial> shell am instrument -w -r
  -e class com.galaxyssi.chat.CollaborationLiveEvidenceDeviceTest
  -e collaborationLiveEvidence true
  -e collaborationLiveHeadless true
  -e collaborationLiveMultipart true
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Join the lines for the local shell. Omitting `collaborationLiveEvidence=true`
skips the real-provider test. Headless and multipart flags are independently
selectable; neither silently enables real requests.

## Scope

Headless mode creates a dedicated persisted conversation without switching the
active conversation, opens the existing MQTT transport, and uses the normal
registered providers, run receipts, health/response ledgers, global slots,
production member worker, scoped evidence import, encrypted workspace and
host-owned acceptance. It does not launch MainActivity or capture the display.
The worker receives a fixed synthetic ScreenContext, not screen/clipboard/
notification contents from the phone. This fixture does not test perception.

The multipart fixture has two people and four assignments:

1. Codex prints a new random fixture token and computes sum/mean for `1,2,4,8`.
   It publishes the observed document and two disjoint source-ID mappings.
2. DeepSeek fetches the actual original observation through scoped recall and
   publishes one delivery review and two exact-version coverage reviews.
3. Codex publishes a saved coverage directory referencing both mapping/review
   pairs, with preserved parent provenance.
4. The coordinator proposes completion using exact document/review references
   and the saved coverage-directory reference. The Android host accepts or
   rejects it using the production checks.

The assertions retain the frozen original-page read-coverage requirement.
Positive text alone, invented references, a summary-read receipt substituted
for the original command, or partial goal coverage cannot pass.

The test uses a dedicated execution database, so a failed fixture does not
automatically expand into the user's research. Cleanup requests durable STOP,
waits for local termination and zero pending remote owners, then removes only
fixture data. An unacknowledged remote stop retains the fixture for recovery.
The active conversation must remain unchanged in headless mode.

## Evidence and limits

Synthetic reports remain in the app's external-files directory:

- `collaboration-live-evidence-mode.json`: run ID, selected test modes, whether
  an activity was launched, and initial lock/interactive state.
- `collaboration-live-evidence.txt`: member states and outputs for that run.
- `collaboration-live-evidence-read-coverage.json`: exact original observations
  and the read-coverage snapshot frozen at review publication, only on success.
- `<run-id>-cleanup.json`: durable STOP and pending remote-owner acknowledgement.

Check run IDs before combining these files; an old successful coverage report
must not be mistaken for evidence from a later failed attempt. Headless mode
does not create a screenshot. Local report files are not committed to GitHub.

This is a small, instrumented, real-provider documentary fixture. Android
instrumentation hosts its process; a pass is not proof that normal background
scheduling survives Doze, process death, reboot, unavailable providers or long
outages. It is not a qualified numerical/scientific experiment, a provider
success-rate estimate, or equal-budget evidence of multi-agent superiority.
The test timeout is a fixture cleanup bound, not a production goal-step limit.

## Remote recall bridge

The first multipart live attempt exposed a real gap: Android persisted exact
dependency receipts and advertised scoped recall in its prompt, but Desktop did
not expose that tool to Codex. Optional prompt sections can be omitted at the
context budget, so a later member could not recover the saved references. The
fixture also incorrectly banned the read needed by its catalogue/delivery nodes.

Desktop now exposes `collaboration_recall` through its existing Codex dynamic
tool interface. It sends an on-demand `collaboration_recall_request` over the
authenticated Link to the originating phone; the phone returns
`collaboration_recall_result`. The model only supplies record/page selectors.
The host supplies route, contact, source-message, conversation, turn, task and
execution generation. The phone checks registered task identity, exact member
binding, live managed-response ownership, membership, pairing, generation and
durable RUN control both before and after reading.

This uses the same `CollaborationScopedRecall` implementation as cloud members:
goal-contract pages, dependency-isolated workspace versions and original tool
observations retain their existing access controls and evidence read coverage.
It cannot inspect the phone screen, read arbitrary chats, change artifacts or
execute another tool. Read-only does not mean unrestricted access.

Queries have nonce and expiry checks, bounded in-flight transport capacity, a
20-second network wait, and cancellation/generation checks. This is a per-read
network timeout, not a research duration or iteration cap. Failed reads return
failure for retry; they never replay a model or external side effect. Neither
request nor response creates a second persistent retry outbox, heartbeat or
periodic polling loop. After restart the saved objects remain and a new scoped
read can retrieve them. Full outage/restart acceptance remains separate.

Codex conversation bindings advance to v7 so new turns do not reuse a thread
whose original tool declaration lacks recall. Existing full-context restoration
is retained; an already active task is not restarted by this version key. The
new tool uses the same canonical `type: function` declaration as existing tools.
Internal recall progress is not counted as public web search.

## Local checks: 2026-10-03

- Android 1.4.28 (1113): both APKs built, 741 JVM tests in 58 suites passed,
  zero failures/errors/skips; upgraded only the authorized S26U in place.
- Desktop 1.4.3: 97 Codex/evidence/MQTT/recall tests and 68 existing JavaScript
  regression tests passed, plus Desktop structure and Kotlin source-size checks.
- The repository-wide check stopped at existing i18n violations in unchanged
  files and local ignored test reports. Those unrelated files were not changed;
  this phase does not claim a clean repository-wide check.
- Desktop was updated only after its global scheduler showed zero active and
  pending tasks. The user's research and other devices were not operated.
- A first post-fix live run failed before Codex execution because the new tool
  initially omitted the canonical declaration type. This was corrected and a
  regression assertion added. The failed fixture acknowledged STOP and removed
  its own data with no pending remote owners; it is not a passing sample.

The final live result is recorded separately below; unit tests do not replace it.

## Live result: 2026-10-03

Run `live-evidence-6c365754-64d2-44a5-969c-09b99418ec22` passed the full
instrumentation fixture in **468.738 seconds** on S26U with actual Codex and
DeepSeek. All four nodes succeeded and the host disposition was `achieved`:

- The author produced a real command observation plus document and two mapping
  parts; the phone imported the original Desktop observation.
- The independent reviewer fetched all **3,301 characters** of that original.
  The review publication froze `host_read_coverage.complete=true`, exact source
  and content hashes, with no missing offset. Reading a summary was insufficient.
- Codex recovered saved references via the authenticated recall bridge and
  published the exact two-part coverage directory.
- The coordinator's final proposal passed the existing host acceptance checks;
  the test resolved the saved directory, both independent mapping reviews and
  the delivery review. No gate was weakened to obtain this result.
- Cleanup confirmed durable STOP, no pending remote owners, and removal of only
  fixture data. The active user conversation was unchanged.

The test started headlessly while Android reported locked/noninteractive;
it did not bypass the lock screen or read its content. This proves this
instrumented provider flow, not normal-app Doze survival or screenshot/UI polish.
Another **34 local S26U regression tests passed in 5.403 seconds** after the live
run, covering scoped recall, evidence persistence, acceptance and atomic inbox.

This one passing run is not a 100% success-rate claim: earlier attempts failed
and led to the fixes above. The 7m49s duration also leaves substantial latency
and prompt/recall efficiency work. Scientific validation, equal-budget team
superiority and a complete outage/Doze/reboot matrix remain unproven. An existing
Desktop reputation-ledger `head_signature_invalid` warning was observed and was
not suppressed or repaired by this change; the original tool-evidence and host
acceptance checks passed independently of that reputation ledger.
