package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
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

    @Test fun summaryExplainsNextStepAndTracksCurrentResearchWithoutFillingChat() {
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
                fun state(label: Int) = await(scenario) {
                    (find(it, "agent-health-care-state") as? TextView)?.text?.toString() ==
                        it.getString(R.string.health_agent_research_state, it.getString(label))
                }
                state(R.string.health_research_queued)
                await(scenario) { !it.findViewById<View>(R.id.startupConnectingView).isShown }
                scenario.onActivity {
                    assertFalse(find(it, "agent-health-care-why")!!.isShown)
                    assertTrue((find(it, "agent-health-care-next") as TextView).text.toString().contains(it.getString(R.string.health_agent_next_plan)))
                    assertFalse(find(it, "agent-health-care-discuss")!!.isShown)
                    assertFalse(find(it, "agent-health-care-plan")!!.isShown)
                    assertTrue(it.findViewById<View>(R.id.agentOutputViewport).height > 0)
                }
                capture("health-agent-summary-fixture.png")
                scenario.onActivity { find(it, "agent-health-care-expand")!!.performClick() }
                await(scenario) { find(it, "agent-health-care-plan")!!.isShown }
                scenario.onActivity {
                    assertTrue(find(it, "agent-health-care-why")!!.isShown)
                    assertTrue(find(it, "agent-health-care-discuss")!!.isShown)
                    val panel = find(it, "agent-health-care-scroll") as ScrollView
                    val cap = (300 * it.resources.displayMetrics.density + .5f).toInt()
                    assertTrue(panel.height in 1..cap)
                    assertTrue(it.findViewById<View>(R.id.agentOutputViewport).height > 0)
                    panel.smoothScrollTo(0, panel.getChildAt(0).height)
                }
                capture("health-agent-summary-expanded-fixture.png")
                job = HealthCareStore(context, names.care).use { it.updateResearchJob(job, HealthCareResearchState.DISPATCHED) }
                state(R.string.health_research_running)
                scenario.onActivity { assertTrue(find(it, "agent-health-care-plan")!!.isShown) }
                job = HealthCareStore(context, names.care).use { HealthCareModelReviewTestFixture.complete(it, job) }
                state(R.string.health_research_completed)
                HealthCareStore(context, names.care).use { care ->
                    val issue = care.concern(plan.grant.concernId)!!
                    val now = System.currentTimeMillis()
                    care.update(issue.id, issue.revision, "synthetic_display_deadline") {
                        it.copy(actions = listOf(HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.RECHECK,
                            "合成到期显示测试", "Synthetic UI timing only, not a clinical recommendation", "Synthetic fixture",
                            HealthCareActionState.CONFIRMED, now + 5000, now + 10000, now,
                            basis = HealthCareFollowUpPolicy.basis(it))))
                    }
                }
                await(scenario) { find(it, "agent-health-care-followup") != null }
                state(R.string.health_research_completed)
                state(R.string.health_research_queued)
                HealthCareStore(context, names.care).use { assertEquals(job, it.latestResearchJob(plan.grant.concernId)) }
                HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                    mapOf("glucose" to "6.4"), "mmol/L", System.currentTimeMillis() - 1, reference = "4-6")) }
                await(scenario) { find(it, "agent-health-care-concern")?.let(::views)?.filterIsInstance<TextView>()
                    ?.any { text -> text.text.toString().contains("6.4") } == true }
                state(R.string.health_research_queued)
                scenario.onActivity { assertNull(find(it, "agent-health-care-plan")) }
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
                await(scenario) { find(it, "agent-health-care-state") == null && find(it, "agent-health-care-discuss") == null }
                scenario.onActivity {
                    it.healthCareSurface!!.pause()
                    assertEquals(View.GONE, it.findViewById<View>(R.id.agentHealthCareSurface).visibility)
                    assertNull(find(it, "agent-health-care-why"))
                }
            }
        } finally {
            worker?.awaitTermination(10, TimeUnit.SECONDS)
            transcripts.switchConversation(previous); if (temporaryId.isNotEmpty()) transcripts.deleteConversation(temporaryId)
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
}
