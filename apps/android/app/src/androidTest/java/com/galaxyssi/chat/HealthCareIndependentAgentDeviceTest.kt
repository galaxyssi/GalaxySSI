package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.ScrollView
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

    @Test fun fullAssessmentCollapsesWithoutCoveringTheTranscriptAndStaysCollapsedAfterRefresh(): Unit = fixture { f ->
        val health = open(f, f.glucose)
        scenario(f, health) { scenario, worker ->
            await(scenario) { (find(it, "agent-health-care-panel")?.height ?: 0) > 0 }
            var collapsedHeight = 0
            var expandedHeight = 0
            var collapsedChatHeight = 0
            scenario.onActivity {
                val panel = find(it, "agent-health-care-panel")!!
                collapsedHeight = panel.height
                collapsedChatHeight = it.findViewById<View>(R.id.agentOutputViewport).height
                assertTrue(collapsedHeight > 0)
                assertFalse(find(it, "agent-health-care-why")!!.isShown)
                assertEquals(it.getString(R.string.health_agent_expand), find(it, "agent-health-care-expand")!!.contentDescription)
                find(it, "agent-health-care-expand")!!.performClick()
            }
            await(scenario) { find(it, "agent-health-care-panel")!!.height > collapsedHeight }
            scenario.onActivity {
                val panel = find(it, "agent-health-care-panel")!!
                expandedHeight = panel.height
                assertTrue(expandedHeight <= (300 * it.resources.displayMetrics.density + .5f).toInt())
                val chat = it.findViewById<View>(R.id.agentOutputViewport)
                assertTrue(chat.height > 0); assertTrue(chat.height < collapsedChatHeight)
                val why = find(it, "agent-health-care-why") as TextView
                assertTrue(why.isShown); assertNull(why.ellipsize)
                assertEquals(Int.MAX_VALUE, why.maxLines)
                for (line in 0 until why.layout.lineCount) assertEquals(0, why.layout.getEllipsisCount(line))
                val scroll = find(it, "agent-health-care-scroll") as ScrollView
                scroll.scrollTo(0, scroll.getChildAt(0).height)
            }
            await(scenario) { (find(it, "agent-health-care-scroll") as ScrollView).scrollY > 0 }
            scenario.onActivity {
                val toggle = find(it, "agent-health-care-expand")!!
                assertTrue(toggle.isShown)
                assertEquals(it.getString(R.string.health_agent_collapse), toggle.contentDescription)
                toggle.performClick()
            }
            await(scenario) { find(it, "agent-health-care-panel")!!.height == collapsedHeight }
            HealthCareStore(context, f.names.care).use { care ->
                val issue = care.concern(f.glucose)!!
                care.update(issue.id, issue.revision, "synthetic_collapsed_refresh") { it }
            }
            worker.submit {}.get(10, TimeUnit.SECONDS); instrumentation.waitForIdleSync()
            scenario.onActivity {
                assertFalse(find(it, "agent-health-care-why")!!.isShown)
                assertEquals(collapsedChatHeight, it.findViewById<View>(R.id.agentOutputViewport).height)
                assertTrue(find(it, "agent-health-care-panel")!!.height < expandedHeight)
            }
            capture("health-panel-collapsed-fixture.png")
            scenario.onActivity { find(it, "agent-health-care-expand")!!.performClick() }
            await(scenario) { find(it, "agent-health-care-why")!!.isShown }
            capture("health-panel-expanded-fixture.png")
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(find(it, "agent-health-care-panel")) }
            scenario.moveToState(Lifecycle.State.RESUMED)
            await(scenario) { find(it, "agent-health-care-panel") != null }
            scenario.onActivity { assertFalse(find(it, "agent-health-care-why")!!.isShown) }
        }
    }

    @Test fun assessmentLayoutBoundsItsBodyAtPhoneAndTabletWidths(): Unit = fixture { f ->
        scenario(f) { scenario, _ -> scenario.onActivity { activity ->
            val ui = HealthCenterViews(activity)
            for (width in listOf(240, 320, 480, 800)) for (height in listOf(320, 600)) {
                val panel = HealthCareAgentPanel(activity, "合成健康评估 · 需要重新评估", "合成记录 6.3 mmol/L",
                    "优先核对这次合成读数", true) {}
                panel.content.addView(ui.text("完整合成说明，用于检查滚动和文字布局。".repeat(30)))
                panel.measure(View.MeasureSpec.makeMeasureSpec(ui.dp(width), View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(ui.dp(height), View.MeasureSpec.AT_MOST))
                panel.layout(0, 0, panel.measuredWidth, panel.measuredHeight)
                val heading = panel.getChildAt(0) as ViewGroup
                val toggle = panel.findViewWithTag<View>("agent-health-care-expand")
                assertTrue(panel.height <= minOf(ui.dp(300), (ui.dp(height) * .4f).toInt()))
                assertTrue(heading.getChildAt(0).right <= toggle.left)
                assertTrue(toggle.bottom <= heading.height)
                assertTrue(panel.scroll.top >= heading.bottom)
                assertTrue(panel.scroll.height > 0)
                assertTrue(panel.scroll.getChildAt(0).height > panel.scroll.height)
            }
        } }
    }
}
