package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.EditText
import android.widget.ListView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAssistantFollowUpDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val zone = ZoneId.systemDefault()
    private val end = LocalDate.now(zone).minusDays(1)
    private val firstQuestion = "\u6700\u8fd1\u7684\u7761\u7720\u6570\u636e\u591f\u5417\uff1f\u4f9d\u636e\u662f\u54ea\u6761\u8bb0\u5f55\uff1f"
    private val secondQuestion = "\u8fd9\u80fd\u8bf4\u660e\u6211\u751f\u75c5\u4e86\u5417\uff1f"
    private val destination = "test.example / scoped-test"
    private val outside = """{"status":"OUT_OF_SCOPE","sections":[],"actions":[]}"""

    private class Gateway : HealthAnalysisGateway {
        val received = CopyOnWriteArrayList<JSONObject>()
        @Volatile var available = true
        private val target = HealthAnalysisTarget("fake", "Scoped model fixture", "scoped-test",
            "https://test.example/model", "openai", "test.example", "test.example")
        override fun targets(context: Context) = if (available) listOf(target) else emptyList()
        override suspend fun exchange(context: Context, expected: HealthAnalysisTarget, payload: JSONObject,
            mode: HealthAnalysisRequest, validate: () -> Unit): String {
            assertEquals(target, expected)
            assertEquals(HealthAnalysisRequest.FOLLOW_UP, mode)
            validate()
            received += JSONObject(payload.toString())
            if (received.size > 1) return """{"status":"OUT_OF_SCOPE","sections":[],"actions":[]}"""
            val facts = payload.getJSONArray("facts")
            val sleep = (0 until facts.length()).map { facts.getJSONObject(it) }
                .single { it.getString("metric") == HealthMetric.SLEEP_DURATION.name }.getString("id")
            return JSONObject().put("status", "PARTIAL").put("sections", JSONArray(listOf("COVERAGE", "SOURCES").map {
                JSONObject().put("topic", it).put("fact_ids", JSONArray(listOf(sleep)))
            })).put("actions", JSONArray()).toString()
        }
    }

    @Test fun nativeConsentUsesExactPayloadAndFollowUpOpensExactRecordRevision() = fixture { names ->
        val record = saveSleep(names)
        grant(names, true)
        val gateway = Gateway()
        launch(names, gateway).use { scenario ->
            click(scenario, "health-assistant-calculate")
            edit(scenario, firstQuestion)
            val declined = choose(scenario)
            assertEquals(firstQuestion, declined.getString("question"))
            dialogButton(android.R.id.button2)
            assertTrue(gateway.received.isEmpty())
            assertDraft(scenario, firstQuestion)
            val first = choose(scenario)
            assertFalse(first.has("previous_answer"))
            dialogButton(android.R.id.button1)
            awaitTag(scenario, "health-follow-up-turn-0") { turn ->
                val lines = labels(turn)
                lines.contains(context.getString(R.string.health_follow_up_partial)) &&
                    lines.contains(context.getString(R.string.health_follow_up_coverage)) &&
                    lines.contains(context.getString(R.string.health_follow_up_sources)) &&
                    views(turn).count { it.tag == "health-follow-up-source" } == 1
            }
            assertEquals(first.toString(), gateway.received.single().toString())
            assertDraft(scenario, "")
            assertFalse(first.toString().contains(record.id))
            assertFalse(first.toString().contains("PRIVATE_FIXTURE_NOTE"))
            screenshot()
            edit(scenario, secondQuestion)
            val second = choose(scenario)
            assertEquals(secondQuestion, second.getString("question"))
            assertFalse(second.toString().contains(firstQuestion))
            assertEquals("PARTIAL", second.getJSONObject("previous_answer").getString("status"))
            dialogButton(android.R.id.button1)
            awaitTag(scenario, "health-follow-up-turn-1") { labels(it).contains(context.getString(R.string.health_follow_up_outside)) }
            assertEquals(second.toString(), gateway.received.last().toString())
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val events = privacy.page().entries.filter { it.scope.purpose == HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE }
                assertEquals(2, events.size)
                assertTrue(events.all { it.outcome == HealthAccessOutcome.COMPLETE && it.scope.destination == destination })
                assertFalse(events.any { it.json().toString().contains(firstQuestion) || it.json().toString().contains(secondQuestion) })
            }
            val monitor = instrumentation.addMonitor(HealthRecordRevisionActivity::class.java.name, null, false)
            val detail = try {
                click(scenario, "health-follow-up-source")
                requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 10_000))
            } finally { instrumentation.removeMonitor(monitor) }
            try {
                assertEquals(names, detail.intent.healthNavigationDatabases())
                assertEquals(record.id, detail.intent.getStringExtra("health_record"))
                assertEquals(record.revision, detail.intent.getIntExtra("health_revision", 0))
                await("record revision") {
                    var loaded = false
                    instrumentation.runOnMainSync {
                        loaded = detail.window.decorView.findViewWithTag<TextView>("health-revision-value")?.text ==
                            healthDisplayValue(record.draft)
                    }
                    loaded
                }
            } finally { instrumentation.runOnMainSync { detail.finish() } }
        }
    }

    @Test fun staleConsentIsDismissedAndUnavailableProviderKeepsDraftUntilBackground() = fixture { names ->
        saveSleep(names)
        grant(names, true)
        val gateway = Gateway()
        launch(names, gateway).use { scenario ->
            click(scenario, "health-assistant-calculate")
            edit(scenario, firstQuestion)
            choose(scenario)
            grant(names, false)
            awaitTag(scenario, "health-assistant-status") {
                (it as TextView).text == context.getString(R.string.health_assistant_changed)
            }
            scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>("health-follow-up-input")) }
            assertTrue(gateway.received.isEmpty())
            grant(names, true)
            gateway.available = false
            click(scenario, "health-assistant-calculate")
            edit(scenario, firstQuestion)
            click(scenario, "health-follow-up-send")
            awaitTag(scenario, "health-assistant-status") {
                (it as TextView).text == context.getString(R.string.health_assistant_no_model)
            }
            assertDraft(scenario, firstQuestion)
            assertTrue(gateway.received.isEmpty())
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            click(scenario, "health-assistant-calculate")
            awaitTag(scenario, "health-follow-up-input") { (it as EditText).text.isEmpty() }
        }
    }

    @Test fun changedRecordCannotProduceAVisibleOrAuditedSuccessfulFollowUp() = fixture { names ->
        val record = saveSleep(names)
        grant(names, true)
        val scope = HealthWeeklyScope(end, zone, setOf(HealthMetric.SLEEP_DURATION))
        val preview = HealthAnalysis.prepare(context, names, scope, HealthAnalysisFocus.CHANGES)
        val question = requireNotNull(HealthFollowUpQuestion.from(firstQuestion))
        assertThrows(HealthWeeklyChanged::class.java) {
            runBlocking {
                HealthAnalysis.followUp(context, names, preview, destination, question) { _, guard ->
                    guard()
                    HealthRecordStore(context, names.records).use { assertTrue(it.delete(record.id, record.revision)) }
                    outside
                }
            }
        }
        HealthPrivacyStore(context, names.privacy).use {
            val event = it.page().entries.single { event -> event.scope.purpose == HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE }
            assertEquals(HealthAccessOutcome.FAILED, event.outcome)
            assertFalse(event.json().toString().contains(firstQuestion))
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun launch(names: HealthOverviewDatabases, gateway: Gateway): ActivityScenario<HealthAssistantActivity> {
        assumeFalse("Visible consent tests require an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        return ActivityScenario.launch<HealthAssistantActivity>(Intent(context, HealthAssistantActivity::class.java)
            .putExtra("health_assistant_test_id", names.fixture)).also {
            it.onActivity { activity -> activity.useFixtureGateway(gateway) }
        }
    }
    private fun saveSleep(names: HealthOverviewDatabases) = HealthRecordStore(context, names.records).use { store ->
        (store.save(HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "6"), "h",
            end.atTime(7, 30).atZone(zone).toInstant().toEpochMilli(), note = "PRIVATE_FIXTURE_NOTE")) as HealthSaveResult.Saved).record
    }
    private fun grant(names: HealthOverviewDatabases, allow: Boolean) = HealthPrivacyStore(context, names.privacy).use {
        it.change(HealthPrivacyOption.ONLINE_ANALYSIS, allow, it.policy().version)
    }
    private fun edit(scenario: ActivityScenario<HealthAssistantActivity>, value: String) =
        awaitTag(scenario, "health-follow-up-input") { (it as EditText).setText(value); true }
    private fun assertDraft(scenario: ActivityScenario<HealthAssistantActivity>, value: String) =
        awaitTag(scenario, "health-follow-up-input") { (it as EditText).text.toString() == value }
    private fun click(scenario: ActivityScenario<HealthAssistantActivity>, tag: String) =
        awaitTag(scenario, tag) { it.isEnabled && it.performClick() }
    private fun choose(scenario: ActivityScenario<HealthAssistantActivity>): JSONObject {
        click(scenario, "health-follow-up-send")
        withDialog("model picker") { roots ->
            val list = roots.filterIsInstance<ListView>().lastOrNull { it.adapter?.count == 1 } ?: return@withDialog false
            val row = list.getChildAt(0) ?: return@withDialog false
            list.performItemClick(row, 0, list.adapter.getItemId(0))
        }
        var payload: JSONObject? = null
        withDialog("exact consent") { roots ->
            val message = roots.filterIsInstance<TextView>().lastOrNull { it.id == android.R.id.message }
                ?.text?.toString().orEmpty()
            if (!message.contains(destination) || !message.contains("\n\n{")) return@withDialog false
            payload = JSONObject(message.substring(message.indexOf("\n\n{") + 2))
            true
        }
        return requireNotNull(payload)
    }
    private fun dialogButton(id: Int) = withDialog("consent button") { roots ->
        roots.lastOrNull { it.id == id }?.performClick() == true
    }
    private fun withDialog(label: String, predicate: (List<View>) -> Boolean) = await(label) {
        var found = false
        instrumentation.runOnMainSync { found = predicate(WindowInspector.getGlobalWindowViews().flatMap(::views)) }
        found
    }
    private fun awaitTag(scenario: ActivityScenario<HealthAssistantActivity>, tag: String, predicate: (View) -> Boolean) = await(tag) {
        var found = false
        scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag)?.let(predicate) == true }
        found
    }
    private fun labels(view: View) = views(view).filterIsInstance<TextView>().map { it.text.toString() }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun screenshot() {
        if (InstrumentationRegistry.getArguments().getString("healthFollowUpScreenshot") != "true") return
        instrumentation.waitForIdleSync()
        SystemClock.sleep(350)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.cacheDir, "health-assistant-follow-up.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        } } finally { bitmap.recycle() }
    }
    private fun await(label: String, predicate: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 16_000
        do { if (predicate()) return; SystemClock.sleep(60) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
