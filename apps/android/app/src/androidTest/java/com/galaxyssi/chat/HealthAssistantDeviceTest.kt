package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAssistantDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.systemDefault()
    private val scope = HealthWeeklyScope(LocalDate.now(zone).minusDays(1), zone,
        setOf(HealthMetric.SLEEP_DURATION, HealthMetric.STEPS))
    private val reply = """{"fact_ids":["f1"],"actions":["WEEKLY_REPORT"]}"""
    private val destination = "model.test / model-one"

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }

    private fun sleep(names: HealthOverviewDatabases, time: Long = scope.from): HealthObservation =
        HealthRecordStore(context, names.records).use { store ->
            (store.save(HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "6"), "h", time,
                note = "PRIVATE_FIXTURE_NOTE")) as HealthSaveResult.Saved).record
        }

    private fun grant(names: HealthOverviewDatabases, allow: Boolean) = HealthPrivacyStore(context, names.privacy).use {
        it.change(HealthPrivacyOption.ONLINE_ANALYSIS, allow, it.policy().version)
    }

    private fun prepare(names: HealthOverviewDatabases, focus: HealthAnalysisFocus = HealthAnalysisFocus.CHANGES) =
        HealthAnalysis.prepare(context, names, scope.copy(comparison = focus == HealthAnalysisFocus.CHANGES), focus)

    @Test fun recentAndBaselineReferencesBindExactRevisionsButAreNeverSent() = fixture { names ->
        val recent = sleep(names)
        val baseline = sleep(names, scope.from - 60_000L)
        val preview = prepare(names)
        val fact = preview.facts.single { it.stat.metric == HealthMetric.SLEEP_DURATION }
        assertEquals(listOf(recent.id to recent.revision, baseline.id to baseline.revision), fact.refs.map { it.id to it.revision })
        assertEquals(listOf(false, true), fact.refs.map { it.baseline })
        assertEquals(1, fact.stat.validDays)
        assertNull(preview.weekly.sleep?.deltaMinutes)
        val payload = HealthAnalysis.payload(preview).toString()
        for (excluded in listOf(recent.id, baseline.id, "PRIVATE_FIXTURE_NOTE", scope.end.toString(), "profile", "timezone", "delta_min")) {
            assertFalse(excluded, payload.contains(excluded))
        }
        assertTrue(payload.contains("\"mean\":\"360\""))
        assertFalse(HealthAnalysis.payload(prepare(names, HealthAnalysisFocus.NEXT_RECORDS)).toString().contains("mean"))
        assertFalse(HealthAnalysis.payload(prepare(names, HealthAnalysisFocus.COVERAGE)).toString().contains("mean"))
    }

    @Test fun rejectsUnboundFactsDuplicateFactsAdviceAndTrailingOutput() = fixture { names ->
        sleep(names)
        val preview = prepare(names)
        assertEquals(listOf("f1"), HealthAnalysis.decodeReply(reply, preview).factKeys)
        for (invalid in listOf(
            reply.replace("f1", "f99"), reply.replace("\"f1\"", "\"f1\",\"f1\""), reply.replace("WEEKLY_REPORT", "TAKE_MEDICINE"),
            reply.dropLast(1) + ",\"summary\":\"invented\"}", reply + " unexpected text"
        )) assertTrue(runCatching { HealthAnalysis.decodeReply(invalid, preview) }.exceptionOrNull() is HealthAnalysisInvalidReply)
    }

    @Test fun noDefaultDisclosureAndStaleRecordCannotReachExchange() = fixture { names ->
        val record = sleep(names)
        val blocked = prepare(names)
        var exchanges = 0
        fun attempt(preview: HealthAnalysisPreview) = runCatching {
            runBlocking { HealthAnalysis.explain(context, names, preview, destination) { _, _ -> exchanges++; reply } }
        }.exceptionOrNull()
        assertTrue(attempt(blocked) is HealthAccessBlocked)
        grant(names, true)
        val stale = prepare(names)
        HealthRecordStore(context, names.records).use { it.delete(record.id, record.revision) }
        assertTrue(attempt(stale) is HealthWeeklyChanged)
        assertEquals(0, exchanges)
    }

    @Test fun inFlightRevocationAndRegrantCannotPublishModelResult() = fixture { names ->
        sleep(names)
        grant(names, true)
        val preview = prepare(names)
        val failure = runCatching {
            runBlocking { HealthAnalysis.explain(context, names, preview, destination) { _, guard ->
                guard()
                grant(names, false)
                grant(names, true)
                reply
            } }
        }.exceptionOrNull()
        assertTrue(failure is HealthWeeklyChanged)
        HealthPrivacyStore(context, names.privacy).use {
            val record = it.page().entries.single { entry -> entry.scope.purpose == HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE }
            assertEquals(destination, record.scope.destination)
            assertEquals(HealthAccessOutcome.FAILED, record.outcome)
            assertFalse(record.json().toString().contains("PRIVATE_FIXTURE_NOTE"))
        }
    }

    @Test fun confirmedModelPlanOnlyReturnsApprovedActionsAndKeepsLocalEvidence() = fixture { names ->
        sleep(names)
        grant(names, true)
        val preview = prepare(names)
        val result = runBlocking { HealthAnalysis.explain(context, names, preview, destination) { data, guard ->
            guard()
            assertEquals(HealthAnalysis.payload(preview).toString(), data.toString())
            reply
        } }
        assertEquals(listOf(HealthAnalysisAction.WEEKLY_REPORT), result.actions)
        assertEquals(listOf("f1"), result.factKeys)
        HealthPrivacyStore(context, names.privacy).use {
            assertEquals(HealthAccessOutcome.COMPLETE,
                it.page().entries.single { entry -> entry.scope.purpose == HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE }.outcome)
        }
    }

    @Test fun providerBodiesDoNotAdvertiseToolsAndRejectInjectedCalls() {
        fun contact(style: String, endpoint: String) = JSONObject().put("id", "fixture").put("delivery_mode", "cloud_api")
            .put("cloud_provider", "custom").put("cloud_model", "health-fixture").put("cloud_api_style", style)
            .put("cloud_api_key", "private-fixture-credential").put("cloud_endpoint", endpoint)
        val base = "https://model.test/v1"
        assertNull(HealthAnalysisProvider.target(contact("openai", "http://model.test/v1")))
        assertNull(HealthAnalysisProvider.target(contact("openai", "$base?token=secret")))
        for ((style, path) in listOf("openai" to "/chat/completions", "anthropic" to "/messages", "gemini" to "/models/health-fixture:generateContent")) {
            val target = requireNotNull(HealthAnalysisProvider.target(contact(style, base + path)))
            val body = HealthAnalysisProvider.body(target, "fixture-summary")
            assertFalse(body.has("tools"))
            assertTrue(body.toString().contains("fixture-summary"))
            assertFalse(body.toString().contains("private-fixture-credential"))
        }
        val bad = JSONObject().put("choices", JSONArray().put(JSONObject().put("message",
            JSONObject().put("content", reply).put("tool_calls", JSONArray().put(JSONObject())))))
        assertTrue(runCatching { HealthAnalysisProvider.decode("openai", bad) }.exceptionOrNull() is HealthAnalysisInvalidReply)
    }

    @Test fun nativeScreenShowsSourcesAndInvalidatesResultsOnRecordEdit() = fixture { names ->
        assumeFalse("Health assistant UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val row = sleep(names)
        fun find(root: View, tag: String): View? = if (root.tag == tag) root else if (root is ViewGroup)
            (0 until root.childCount).firstNotNullOfOrNull { find(root.getChildAt(it), tag) } else null
        val intent = Intent(context, HealthAssistantActivity::class.java).putExtra("health_assistant_test_id", names.fixture)
        ActivityScenario.launch<HealthAssistantActivity>(intent).use { scenario ->
            fun await(tag: String) {
                val limit = SystemClock.elapsedRealtime() + 15_000
                do {
                    var exists = false
                    scenario.onActivity { exists = find(it.window.decorView, tag) != null }
                    if (exists) return
                    SystemClock.sleep(40)
                } while (SystemClock.elapsedRealtime() < limit)
                fail("Missing native view: $tag")
            }
            scenario.onActivity {
                assertNull(find(it.window.decorView, "health-assistant-source"))
                assertTrue(requireNotNull(find(it.window.decorView, "health-assistant-calculate")).performClick())
            }
            await("health-assistant-source")
            HealthRecordStore(context, names.records).use { it.delete(row.id, row.revision) }
            await("health-assistant-status")
            scenario.onActivity {
                assertNull(find(it.window.decorView, "health-assistant-source"))
                assertEquals(it.getString(R.string.health_assistant_changed),
                    (find(it.window.decorView, "health-assistant-status") as TextView).text.toString())
            }
        }
    }
}
