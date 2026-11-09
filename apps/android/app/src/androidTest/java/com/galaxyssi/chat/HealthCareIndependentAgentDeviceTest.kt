package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareIndependentAgentDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: MainActivity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<MainActivity>, predicate: (MainActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do {
            var ready = false; scenario.onActivity { ready = predicate(it) }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Independent health conversation did not reach the expected state")
    }
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { bitmap.recycle() } }
    }
    private class Fixture(val names: HealthOverviewDatabases, val transcripts: AgentTranscriptStore,
        val glucose: String, val pressure: String, val ordinary: String, val ids: MutableSet<String>)
    private fun fixture(test: (Fixture) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val transcripts = AgentTranscriptStore(context); val previous = transcripts.activeConversation().id
        val ids = mutableSetOf<String>()
        try {
            HealthRecordStore(context, names.records).use {
                it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L",
                    System.currentTimeMillis() - 1000, reference = "4-6"))
                it.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "185", "diastolic" to "90"), "mmHg",
                    System.currentTimeMillis() - 1000))
            }
            HealthCareStore(context, names.care).use { it.configure(true, it.settings().version) }
            HealthCareEngine.evaluate(context, names)
            val concerns = HealthCareStore(context, names.care).use {
                it.forMetric(HealthMetric.GLUCOSE)!!.id to it.forMetric(HealthMetric.BLOOD_PRESSURE)!!.id
            }
            val ordinary = transcripts.createAgentConversation("普通会话隔离测试").id.also(ids::add)
            transcripts.switchConversation(ordinary)
            test(Fixture(names, transcripts, concerns.first, concerns.second, ordinary, ids))
        } finally {
            transcripts.switchConversation(previous)
            ids.forEach(transcripts::deleteConversation)
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
    private fun open(fixture: Fixture, concern: String) = HealthCareDiscussion.open(context, concern, fixture.names).also(fixture.ids::add)
    private fun scenario(fixture: Fixture, id: String = fixture.ordinary,
        test: (ActivityScenario<MainActivity>, ExecutorService) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", id)).use { scenario ->
                await(scenario) { it.agentTranscriptStore.activeConversation().id == id && !it.findViewById<View>(R.id.startupConnectingView).isShown }
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, fixture.names).also { surface ->
                        worker = surface.javaClass.getDeclaredField("worker").apply { isAccessible = true }.get(surface) as ExecutorService
                        surface.showForAgent(true); surface.resume()
                    }
                }
                test(scenario, worker!!)
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
    private fun select(scenario: ActivityScenario<MainActivity>, id: String) {
        scenario.onActivity {
            it.agentTranscriptStore.switchConversation(id)
            it.selectConversationOutputPage(false)
            assertEquals(View.GONE, it.findViewById<View>(R.id.agentHealthCareSurface).visibility)
            assertNull(find(it, "agent-health-care-concern"))
        }
    }
    private fun label(activity: MainActivity) = find(activity, "agent-health-care-concern")?.let(::views)
        ?.filterIsInstance<TextView>()?.joinToString { it.text.toString() }.orEmpty()

    @Test fun openingIsDurableIdempotentAndDoesNotDispatchOrSelectAnAgent(): Unit = fixture { f ->
        val health = open(f, f.glucose)
        repeat(4) { assertEquals(health, open(f, f.glucose)) }
        val reopened = AgentTranscriptStore(context)
        assertEquals(f.ordinary, reopened.activeConversation().id)
        val conversation = reopened.conversation(health)!!
        assertTrue(conversation.privateMode); assertTrue(conversation.trackingPaused); assertTrue(conversation.createdByAgent)
        assertEquals(f.glucose, HealthCareAgentScope.concernId(conversation))
        assertTrue(reopened.conversationPage(AgentConversationStatus.ACTIVE, pageSize = 100).items.any { it.id == health })
        assertEquals("", conversation.latestMessageEntryId)
        HealthCareStore(context, f.names.care).use {
            assertEquals(f.glucose, it.discussion(health)); assertNull(it.latestResearchJob(f.glucose))
            assertNull(it.researchAuthorization(f.glucose)); assertTrue(it.pendingPlans(f.glucose).isEmpty())
        }
        assertNotEquals(health, open(f, f.pressure))
    }
    @Test fun ordinaryChatStaysEmptyAndSwitchingClearsHealthBeforeLoading(): Unit = fixture { f ->
        val health = open(f, f.glucose)
        scenario(f) { scenario, worker ->
            worker.submit {}.get(10, TimeUnit.SECONDS); instrumentation.waitForIdleSync()
            scenario.onActivity { assertNull(find(it, "agent-health-care-concern")) }
            capture("health-independent-ordinary-fixture.png")
            select(scenario, health)
            await(scenario) { label(it).contains(it.getString(HealthMetric.GLUCOSE.titleResource())) }
            capture("health-independent-discussion-fixture.png")
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(find(it, "agent-health-care-concern")) }
            scenario.moveToState(Lifecycle.State.RESUMED)
            await(scenario) { find(it, "agent-health-care-concern") != null }
            select(scenario, f.ordinary)
            worker.submit {}.get(10, TimeUnit.SECONDS); instrumentation.waitForIdleSync()
            scenario.onActivity { assertNull(find(it, "agent-health-care-concern")) }
        }
    }
    @Test fun differentConcernsAndUnboundTopicsCannotBorrowEachOthersContext(): Unit = fixture { f ->
        val first = open(f, f.glucose); val second = open(f, f.pressure)
        val unbound = f.transcripts.createAgentConversation("未绑定健康会话测试", privateMode = true, trackingPaused = true,
            globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + f.glucose).id.also(f.ids::add)
        scenario(f, first) { scenario, worker ->
            await(scenario) { label(it).contains(it.getString(HealthMetric.GLUCOSE.titleResource())) }
            select(scenario, second)
            await(scenario) { label(it).contains(it.getString(HealthMetric.BLOOD_PRESSURE.titleResource())) }
            scenario.onActivity { assertFalse(label(it).contains(it.getString(HealthMetric.GLUCOSE.titleResource()))) }
            select(scenario, unbound)
            worker.submit {}.get(10, TimeUnit.SECONDS); instrumentation.waitForIdleSync()
            scenario.onActivity { assertEquals(View.GONE, it.findViewById<View>(R.id.agentHealthCareSurface).visibility) }
            select(scenario, second)
            await(scenario) { find(it, "agent-health-care-concern") != null }
            HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
            await(scenario) { find(it, "agent-health-care-concern") == null }
        }
    }
    @Test fun lateHealthLoadCannotReinsertThePanelIntoAnOrdinaryConversation(): Unit = fixture { f ->
        val health = open(f, f.glucose)
        scenario(f) { scenario, worker ->
            val entered = CountDownLatch(1); val release = CountDownLatch(1)
            worker.execute { entered.countDown(); release.await(10, TimeUnit.SECONDS) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            try { select(scenario, health); select(scenario, f.ordinary) } finally { release.countDown() }
            worker.submit {}.get(10, TimeUnit.SECONDS); instrumentation.waitForIdleSync()
            scenario.onActivity { assertNull(find(it, "agent-health-care-concern")) }
            select(scenario, health)
            await(scenario) { find(it, "agent-health-care-concern") != null }
        }
    }
}
