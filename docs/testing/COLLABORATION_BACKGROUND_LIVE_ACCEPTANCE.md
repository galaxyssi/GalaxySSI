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

## Confirmed remote evidence delivery

The follow-up changes the private recall wire contract to
`galaxyssi.collaboration-recall/2`; update both Android and Desktop together.
The model-facing tool name and selectors are unchanged. No legacy-contract
fallback is permitted to credit remote page coverage.

Previously, preparing a remote original-evidence page recorded coverage before
MQTT delivery. A dropped response could therefore leave coverage for a page the
Desktop never received. Remote reads now prepare the page without crediting it:

1. The phone sends the page and an opaque, short-lived delivery challenge.
2. Desktop verifies the full page's UTF-8 SHA-256 and acknowledges the challenge
   using the same authenticated task scope, execution generation and selectors.
3. The phone rechecks current authorization, the challenge and the exact saved
   page. Only then does its existing encrypted ledger merge the confirmed range.
4. Desktop returns the page to the Codex tool interface only after the phone
   confirms the coverage commit. A failed exchange returns a retryable read
   failure, never a successful original-evidence result.

Each exchange retains the existing bounded network timeout. There is no goal
iteration cap, periodic heartbeat or new persistent message outbox. Challenges
are bounded to 128 small in-memory records and expire after 60 monotonic seconds;
they contain selectors and a digest, not page bodies. Confirmed challenges can
be evicted under pressure so they cannot prevent new work. Duplicate confirmations
are safe because the existing ledger merges identical ranges idempotently.
Losing the phone process discards unconfirmed challenges and requires a new
read; saved originals and already confirmed ranges remain in encrypted storage.
Pause, stop, membership revocation and task-generation changes remain gates.

This proves delivery to the trusted Desktop executor, not model comprehension,
source truth or scientific validity. A Desktop crash after acknowledgement can
precede model consumption. Existing host acceptance still requires independent
reviews of exact evidence and freezes coverage at publication. Local cloud and
native recall retain their direct in-process serving behavior.

Fault-injection tests cover missing/corrupt/lost reads and confirmations, phase
mismatch, scope/generation changes, cancellation, expired challenges, storage
failure, duplicate confirmation, and unconfirmed pages after store recreation.
`CollaborationRecallDeliveryDeviceTest` checks the real encrypted phone store.
The multipart live fixture additionally requires the later Codex catalogue node
to read and cite the original command, and checks its frozen coverage separately
from DeepSeek's review. Full device Doze/outage endurance remains a separate
acceptance requirement, not implied by these injected transport faults.

### Follow-up local checks (2026-10-03)

- Android 1.4.29 (1114): final application and instrumentation APKs built;
  751 JVM tests across 59 suites passed with zero failures, errors or skips.
- The cross-platform page digest has a shared fixed UTF-8 test vector containing
  non-ASCII text, quotes, a newline and a supplementary Unicode character.
  The existing JSON-value digest is deliberately not used for wire page bytes.
- Desktop 1.4.4: 104 Python and 68 JavaScript regression tests passed, as did
  Desktop structure, Kotlin source-size and whitespace checks.
- Both APKs were installed only on S26U. The new encrypted-store fixture plus
  existing recall/evidence/acceptance/inbox checks passed: 35 tests in 7.152s.
- Desktop was updated only after both schedulers and its other task list were
  empty. Its Signal sidecar and all three MQTT subscriptions became ready.

### Recall-echo import regression

The first live run of confirmed delivery,
`live-evidence-e3d43ea7-6569-407b-82ed-d0c3bdada0c8`, failed the unchanged
12-minute fixture deadline. Author, independent review and catalogue succeeded;
the final Desktop model also completed, but phone-side import had not finished.
The catalogue's Desktop completion to phone workspace publication took about
202 seconds. Its 13 imported observations included repeated internal recall
responses containing evidence already owned by the phone. This is a failed
sample, not proof of complete delivery acceptance. Cleanup acknowledged STOP,
removed only fixture data and left no pending remote owners.

Desktop now retains every original observation in its encrypted audit archive,
but its authenticated phone-import index excludes the host-registered
`dynamicToolCall` named `collaboration_recall`. Command, file, external MCP and
other dynamic-tool observations are still imported. Full archive indexing and
exact original-page reads remain available; the filtered index explicitly labels
its projection and never claims complete provider history. Old archive entries
default to importable on schema migration. The model cannot set this projection.
Tests check archive retention, migration, peer authorization, exact tool-type
classification and pagination across 90 interleaved internal/external records.

This removes recursive evidence transport, not the original-read acknowledgement
or host acceptance requirement. The next live run uses the same deadline and
checks, including frozen full-page coverage for both DeepSeek and remote Codex.

### Follow-up live attempt and test isolation

Run `live-evidence-db39bae8-1aa1-4844-9cd4-1f2a41d7e48a` began on an unlocked,
interactive S26U. The author and DeepSeek review completed; the catalogue Codex
node started. USB disconnected and the instrumentation output stream was lost.
Independently, running the raw Python unit suite while this live task existed
exposed import-time initialization of the default Desktop task manager. It
advanced the test task's recovery generation and fenced the original executor.
This disrupted attempt is **not** a passing real-provider sample.

The Desktop archive confirms that the author's original command remains
importable, while its one internal recall and the catalogue's thirteen internal
recalls remain archived but excluded from the phone-import projection. These
counts verify classification, not end-to-end completion or latency improvement.
The catalogue was reconciled to a terminal failure by reloading the idle
Desktop; both execution schedulers were empty and no other nonterminal task was
present. Phone cleanup and a fresh full live pass still need verification after
S26U reconnects. Do not reuse a previous run's coverage report as current proof.

Run this regression suite through the isolated entry point from the repository
root, **not** a raw unittest command against a running user's default state:

```sh
python apps/desktop/scripts/test-collaboration-evidence.py
```

The entry point sets temporary home, state, data, configuration, workspace and
Codex directories in a child process before test discovery or backend imports,
disables external services, and propagates its exit code. All 104 tests passed
again in 9.461 seconds in this isolated environment, including migration of
existing encrypted multi-page observations. No full live success is claimed for
the delivery-confirmation follow-up until a clean rerun completes.

After USB reconnected, a narrowly scoped `cleanupRetainedFixture` device check
passed in 12.929 seconds for that interrupted fixture. It required the exact
UUID-prefixed test ID, retained cleanup marker, matching stopped terminal
snapshot, and a non-active conversation. It reconciled the remote terminal
acknowledgement before removing fixture data. The new report confirms durable
STOP, `acknowledged=true`, `retained_for_recovery=false` and no pending remote
owners; the user's active conversation was unchanged. The check never starts a
model or retries the original command.

### Completed live workflow and corrected fixture assertion

Run `live-evidence-9ad4d718-d113-44be-b364-a088dde4c90c` completed all four real
nodes with `state=SUCCEEDED` and `disposition=achieved`. The instrumentation
fixture ended at 536.173 seconds with a **test assertion failure**, not a model
or host-acceptance failure: it required every supplementary reviewer observation
to use `scoped_pages`. The reviewer correctly also cited two of its own local
recall calls, which have the distinct `same_dispatch_execution` provenance.

The corrected fixture still requires the actual peer command reference, full
coverage of that original, independent reviewer identity and a real original
fetch. Every supplementary reference still goes through the existing
`requireComplete` validator; only the mode assertion is restricted to the peer
originals it is intended to test. A mixed-own-and-peer regression verifies that
own tool receipts cannot substitute for unread peer evidence. No production
acceptance rule was changed.

Read-only inspection of the same run's encrypted Desktop archive, with every
original payload SHA-256 checked, independently verified:

- The remote Codex response contains the delivery-confirmed marker for the
  original 3,301-character command record.
- DeepSeek's review and Codex's saved directory both freeze complete
  `scoped_pages` coverage for that exact evidence ID, source hash and content
  hash, with all six reader-identity fields matching their respective document.
- The two supplementary receipts belong to the reviewer's own dispatch.
- The catalogue's Desktop completion to phone publication was **8.877 seconds**
  (1790993477080 to 1790993485957), compared with approximately 202 seconds in
  the earlier failed sample. This single comparison is not a p95 or success-rate
  claim; one readonly recall timeout was recovered during the run.
- Cleanup acknowledged durable STOP, retained no fixture data and reported no
  pending remote owners. The original research was never run.

The corrected full model-backed instrumentation fixture was **not repeated**
solely to fix its assertion, avoiding another round of provider usage. Thus the
real workflow plus archive validation succeeded, but the recorded JUnit live
run remains failed and must not be relabelled as a clean full-script pass.

After the fixture correction, the instrumentation APK rebuilt successfully and
was installed only on S26U. The full selected collaboration/MQTT JVM suite passed
**752 tests across 59 suites** with zero failures, errors or skips; the 35 local
S26U evidence/acceptance/inbox regressions passed again in **9.776 seconds**.
These checks make no additional model calls. This follow-up changes only tests
and this report, so it does not publish another application version: the running
product remains Android 1.4.29 (1114) and Desktop 1.4.4 from merged PR #3350.

## Clean confirmed-delivery rerun: 2026-10-03

After PR #3351 merged, the authorized S26U reran the unchanged multipart,
headless real-provider fixture. Run
`live-evidence-b98e0f65-a3a4-437c-8f5e-f050cde67606` passed the complete
instrumentation script: **OK (1 test), 543.208 seconds**. All four assignments
were `SUCCEEDED`, the final disposition was `achieved`, and the host-owned
acceptance receipt was accepted. This is a new clean sample; the earlier
assertion-failed and interrupted samples remain failures as recorded above.

The run used Android 1.4.29 (1114), Desktop 1.4.4, actual paired Codex and
configured DeepSeek, and the same 12-minute fixture bound. No production or
assertion changes were made for this rerun. The following checks passed:

- Codex executed the synthetic command and imported its actual observation.
- DeepSeek independently reviewed the document and both goal-mapping parts.
- The later Codex directory assignment also fetched the original evidence.
- Both readers froze `scoped_pages` coverage of all **3,301 / 3,301 characters**
  for the same evidence ID, source hash and content hash, under their own exact
  dispatch identities. A summary or an own-tool receipt did not substitute for
  the peer original.
- Exact-version mappings, independent reviews and the coverage directory
  passed the existing Android host acceptance checks.
- Mode, snapshot, read-coverage and cleanup reports all refer to this run.
  Cleanup acknowledged durable `STOP`, reported no pending remote owners, and
  removed only fixture data (`retained_for_recovery=false`). The user's selected
  conversation was unchanged. Desktop scheduling ended with zero active and
  zero pending tasks.

Selected timings from the Desktop task records and phone workspace receipts:

| Assignment | Desktop execution | Desktop completion to phone publication |
| --- | ---: | ---: |
| Author | 138.175 s | 36.817 s |
| Coverage directory | 178.773 s | 7.562 s |
| Final assessment | 129.116 s | Not measured separately |

For the directory, Desktop completion was `1790995465178` and phone publication
was `1790995472740`; it imported zero internal recall echoes while retaining
the required original-read coverage. The author imported one command record:
completion was `1790995216916`, publication was `1790995253733`. Its **36.817 s**
post-completion delay remains a latency investigation item. The total fixture
time includes model work, real transport, validation and cleanup; it is not a
normal-chat response-time target, a p95, or proof of a general speedup.

Synthetic report files remain local and are not included in this PR. No raw
user conversation, credentials, pairing material or model reasoning is added.
This documentation-only follow-up does not change the application versions.
The pass closes the clean-script acceptance gap for this evidence-delivery
path, not the outstanding Doze/long-outage/reboot matrix, general computational
or scientific validation, candidate-evolution acceptance, or equal-budget
single-Agent versus team quality and cost comparison.
