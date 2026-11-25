package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareAgentSurfaceUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: MainActivity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<MainActivity>, ready: (MainActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do {
            var done = false; scenario.onActivity { done = ready(it) }
            if (done) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Agent health summary did not reach the expected state")
    }
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync(); SystemClock.sleep(300)
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { image.recycle() } }
    }

    @Test fun summaryUsesOnlyTheCurrentRecordAndDoesNotChangeResearch() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val transcripts = AgentTranscriptStore(context)
        val previous = transcripts.activeConversation().id
        var temporaryId = ""
        var worker: ExecutorService? = null
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names, conversation = { concernId ->
                transcripts.createAgentConversation("主动健康摘要测试", globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + concernId,
                    privateMode = true, trackingPaused = true).id.also { temporaryId = it }
            })
            transcripts.switchConversation(temporaryId)
            val consent = HealthCareResearchAuthorization(UUID.randomUUID().toString(), plan.grant, "b".repeat(64))
            var job = HealthCareStore(context, names.care).use {
                it.authorizeResearch(consent, null)
                it.queueResearch(consent.id, plan.grant.concernId, System.currentTimeMillis())
            }
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", temporaryId)).use { scenario ->
                await(scenario) { it.agentTranscriptStore.activeConversation().id == temporaryId }
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, names).also {
                        worker = it.javaClass.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                        it.showForAgent(true); it.resume()
                    }
                }
                fun value(expected: String) = await(scenario) {
                    (find(it, "agent-health-care-value") as? TextView)?.text?.toString() == expected
                }
                await(scenario) {
                    (find(it, "agent-health-care-value") as? TextView)?.text?.toString() ==
                        "6.3 mmol/L" + it.getString(R.string.health_agent_report_reference, "4-6 mmol/L")
                }
                assertTrue(HealthCareModelReviewVisibility.contains(names.care, temporaryId))
                assertFalse(HealthCareModelReviewVisibility.contains(names.care, previous))
                await(scenario) { !it.findViewById<View>(R.id.startupConnectingView).isShown }
                scenario.onActivity {
                    listOf("expand", "why", "next", "discuss", "plan", "followup", "state", "record", "scroll").forEach { tag ->
                        assertNull(find(it, "agent-health-care-$tag"))
                    }
                    assertTrue(it.findViewById<View>(R.id.agentOutputViewport).height > 0)
                }
                capture("health-agent-summary-fixture.png")
                job = HealthCareStore(context, names.care).use { it.updateResearchJob(job, HealthCareResearchState.DISPATCHED) }
                job = HealthCareStore(context, names.care).use { HealthCareModelReviewTestFixture.complete(it, job) }
                HealthCareStore(context, names.care).use { assertEquals(job, it.latestResearchJob(plan.grant.concernId)) }
                HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                    mapOf("glucose" to "6.4"), "mmol/L", System.currentTimeMillis())) }
                value("6.4 mmol/L")
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
                value("6.4 mmol/L")
                scenario.onActivity {
                    it.healthCareSurface!!.pause()
                    assertFalse(HealthCareModelReviewVisibility.contains(names.care, temporaryId))
                    assertEquals(View.GONE, it.findViewById<View>(R.id.agentHealthCareSurface).visibility)
                    assertNull(find(it, "agent-health-care-value"))
                }
            }
        } finally {
            worker?.awaitTermination(10, TimeUnit.SECONDS)
            transcripts.switchConversation(previous); if (temporaryId.isNotEmpty()) transcripts.deleteConversation(temporaryId)
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
}
