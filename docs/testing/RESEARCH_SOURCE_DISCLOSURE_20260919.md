# Search disclosure under the processed row

## Scope

- Android v1.2.7 (1012); Desktop source v1.2.7.
- Add a collapsed search summary directly below the existing processing/processed
  header. Keep the existing process narration, planning row, response and colors.
- Expand in place to show complete recorded query phrases and numbered source
  titles; titles open their HTTP(S) source in the system URL handler.
- No search receipts means no extra row. Plain answers are not parsed to invent
  search counts. Source snippets are references, not a claim of full-text reading
  or factual verification.

## Data and lifecycle

Android streaming and its complete-JSON fallback produce presentation receipts
from actual tool results. `web_research` reports executed queries separately from
its proposed query plan. Recovered cloud observations repopulate the same record.
Query phrases are whitespace-normalized and case-insensitively deduplicated;
source URLs are deduplicated without fragments while preserving query parameters.
Only HTTP(S) URLs with hosts and without embedded user credentials are clickable.

Receipts are stored in the existing encrypted database infrastructure, in small
rows keyed by conversation and turn. They are not added to the model prompt or
global memory. Duplicate deliveries merge idempotently. Conversation deletion
removes the receipts and leaves a tombstone preventing late events from restoring
them. Clearing transcript data clears receipt storage too.

The view loads receipts off the UI thread and subscribes to local changes only
while attached. It builds source TextViews only when expanded. Expansion state
uses the existing bounded per-window section-state map; history contents survive
an app restart, while a fresh window starts collapsed.

Desktop Codex adapters attach explicit native `webSearch` queries and available
result/source/open-page URLs to progress metadata. Task payloads replay recorded
receipts, including on completion/reconnection, independently of narration replay.
Native sources not exposed by Codex are not guessed: the UI says sources were not
supplied when only query receipts exist. The full list of hidden Codex retrieval
results cannot be reconstructed from this interface. Other remote agent adapters
without receipts do not yet contribute counts.

Records are bounded to 128 queries and 512 sources per turn; bounded partial data
is explicitly labeled as a recorded subset. Desktop per-event receipts stay below
12 KB (the event metadata limit is 16 KB); aggregate replay is limited to 48 KB.
Snapshots potentially missing older events are also marked partial.

## Verification

- Android: 36 focused JVM tests passed, including seven new receipt-policy tests.
- Debug APK and Android instrumentation APK: build successful.
- Desktop: 57 research/Codex tests and 45 MQTT task-routing/latency tests passed.
- Added `AgentResearchTraceDeviceTest`: encrypted persistence, scope isolation,
  duplicate handling, deletion/late events, collapsed/expanded transcript UI and
  refresh behavior. Screenshot output: external reports/research-trace-ui.png.
- S26U (SM-S9480, R5GL546G3LZ) was subsequently connected. The debug APK was
  installed with `adb install -r` and launched through StartupActivity; package
  inspection confirmed v1.2.7 (1012). Existing pairing and chat data were retained.
  No installation or interaction was performed on SM-R920. The new instrumented
  interaction tests have NOT run yet; no real-provider end-to-end or visual pass
  is claimed for this change yet.
- Existing replies created before receipt recording are not backfilled from prose.
- Desktop runtime has not been replaced; updated remote receipts require deployment.

## Commands

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.galaxyssi.chat.AgentResearchTraceTest --tests com.galaxyssi.chat.CloudEvidenceCitationsTest --tests com.galaxyssi.chat.CloudCitationPreviewTest --tests com.galaxyssi.chat.CloudWebToolLoopProgressTest --tests com.galaxyssi.chat.AgentWebEvidenceVerificationTest :app:assembleDebug :app:assembleDebugAndroidTest
python -m unittest test_research_trace test_research_quality test_codex_conversation_threads
python -m unittest test_mqtt_task_turn_routing test_task_latency
adb -s R5GL546G3LZ shell am instrument -w -r -e class com.galaxyssi.chat.AgentResearchTraceDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```
