package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthAgentLabDeviceTest {
    private val runner get() = InstrumentationRegistry.getInstrumentation()
    private val ctx get() = runner.targetContext
    private fun uuid() = UUID.randomUUID().toString()
    @Test fun latestReportNotesAndRemindersKeepTheirRecordAndPrivacyBoundaries() {
        val names = HealthOverviewDatabases(uuid())
        val now = System.currentTimeMillis()
        val chat = uuid()
        try {
            HealthCareStore(ctx, names.care).use { it.configure(true, "") }
            assertTrue(HealthAgentLab.read(ctx, names, now).rows.isEmpty())
            val evidence = HealthEvidence(uuid(), uuid(), "fixture", "a".repeat(64), 1, "synthetic", confirmed = true)
            val time = now - 86_400_000L
            val draft = HealthDraft(HealthMetric.LDL, mapOf("ldl" to "4.2"), "mmol/L", time, evidence = evidence, reference = "<3.0")
            HealthRecordStore(ctx, names.records).use { r ->
                assertTrue(r.save(draft) is HealthSaveResult.Saved)
                assertTrue(r.save(draft.copy(measuredAt = time - 172_800_000L, evidence = evidence.copy(originalId = uuid(), jobId = uuid()))) is HealthSaveResult.Saved)
                assertTrue(r.save(draft.copy(metric = HealthMetric.HDL, values = mapOf("hdl" to "1.5"), evidence = evidence.copy(candidateId = "fixture-hdl"), reference = ">1.0")) is HealthSaveResult.Saved)
                assertTrue(r.save(draft.copy(metric = HealthMetric.CHOLESTEROL, values = mapOf("cholesterol" to "5"), evidence = evidence.copy(candidateId = "fixture-tc"), reference = "")) is HealthSaveResult.Saved)
                assertTrue(r.save(draft.copy(metric = HealthMetric.GLUCOSE, values = mapOf("glucose" to "5.1"), measuredAt = now,
                    evidence = null, reference = "4-6")) is HealthSaveResult.Saved)
            }
            val first = HealthAgentLab.read(ctx, names, now)
            val older = HealthAgentLab.read(ctx, names, requireNotNull(first.olderUntil))
            assertTrue(older.day!!.isBefore(first.day)); assertNull(older.olderUntil)
            assertEquals(3, first.rows.size); assertEquals(1, first.unknown)
            val row = first.abnormal.single()
            assertEquals(HealthMetric.LDL, row.draft.metric)
            HealthAgentLab.annotate(ctx, names, row, first.privacy, "after lunch", "after_meal")
            assertTrue(runCatching { HealthAgentLab.annotate(ctx, names, row, first.privacy, "stale", null) }.isFailure)
            val corrected = HealthAgentLab.read(ctx, names, now).abnormal.single()
            assertEquals(row.id, corrected.id); assertEquals("after_meal", corrected.draft.condition)
            assertEquals(evidence, corrected.draft.evidence); assertEquals(draft.values, corrected.draft.values)
            val due = now + 3_600_000L
            HealthAgentLab.schedule(ctx, names, corrected, first.privacy, chat, due)
            HealthAgentLab.schedule(ctx, names, corrected, first.privacy, chat, due + 1000)
            HealthCareStore(ctx, names.care).use { care ->
                val issue = care.forMetric(HealthMetric.LDL)!!
                assertEquals("local-conversation:$chat", issue.actions.single().source)
                assertEquals(due + 1000, care.reminders(issue.id).single().dueAt)
            }
            HealthPrivacyStore(ctx, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
            assertTrue(runCatching { HealthAgentLab.read(ctx, names, now) }.exceptionOrNull() is HealthAccessBlocked)
            val permit = HealthPrivacyStore(ctx, names.privacy).use { HealthAgentLab.Once(it.policy().version, now) }
            val once = HealthAgentLab.read(ctx, names, now, permit)
            assertEquals(row.id, once.abnormal.single().id); assertFalse(once.privacy.metrics)
            assertTrue(runCatching { HealthAgentLab.read(ctx, names, now, permit) }.isFailure)
            assertTrue(runCatching { HealthAgentLab.annotate(ctx, names, corrected, once.privacy, "blocked", null) }.isFailure)
            assertTrue(runCatching { HealthAgentLab.annotate(ctx, names, corrected, first.privacy, "blocked", null) }.isFailure)
        } finally { clearHealthOverviewFixture(ctx, names) }
    }
    @Test fun plainQueriesAndFollowUpsDoNotStealOtherPeopleOrOrdinaryQuestions() {
        assertEquals(HealthAgentLabIntent.ABNORMAL, HealthAgentLab.intent("我的体检异常的指标", false))
        assertEquals(HealthAgentLabIntent.RESULTS, HealthAgentLab.intent("帮我看最近体检结果", false))
        assertEquals(HealthAgentLabIntent.NOTE, HealthAgentLab.intent("那次是餐后两小时测的", true))
        assertEquals(HealthAgentLabIntent.REMIND, HealthAgentLab.intent("医生让我下个月复查", true))
        listOf("我父亲的体检异常指标", "我今天吃什么", "提醒我下个月复查", "那次是餐后测的").forEach { assertNull(HealthAgentLab.intent(it, false)) }
    }
    @Test fun briefReportQuestionsAndScopedEllipsis() {
        assertEquals(HealthAgentLabIntent.ABNORMAL, HealthAgentLab.intent("体检异常指标", false))
        assertNull(HealthAgentLab.intent("检查结果", false))
        assertEquals(HealthAgentLabIntent.RESULTS, HealthAgentLab.intent("检查结果", true))
        for (following in listOf(false, true)) {
            listOf("体检情况", "体检情况？", "请帮我看看上次的体检结果", "最近一次化验报告", "检验指标").forEach {
                assertEquals(it, HealthAgentLabIntent.RESULTS, HealthAgentLab.intent(it, following))
            }
            listOf("体检情况汇报怎么写", "帮我预约体检", "看看朋友的体检报告", "一般人的体检指标是什么意思？",
                "不要看体检情况", "软件测试结果呢").forEach { assertNull(it, HealthAgentLab.intent(it, following)) }
        }
        listOf("结果呢", "看看全部", "所有指标呢").forEach {
            assertNull(it, HealthAgentLab.intent(it, false))
            assertEquals(it, HealthAgentLabIntent.RESULTS, HealthAgentLab.intent(it, true))
        }
        listOf("哪些异常？", "偏高的呢", "异常指标有哪些").forEach {
            assertNull(it, HealthAgentLab.intent(it, false))
            assertEquals(it, HealthAgentLabIntent.ABNORMAL, HealthAgentLab.intent(it, true))
        }
    }
    // Opt-in acceptance on the installed app. Only checks the presence of results, never reads or logs values.
    @Test fun liveQuestionFromMainComposerShowsSavedRecordsWithoutAProvider() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("localLabLive") == "yes")
        val brief = InstrumentationRegistry.getArguments().getString("localLabQuery") == "brief"
        val conversation = AgentTranscriptStore(ctx).activeConversation()
        require(conversation.globalTopicKey.isBlank())
        val monitor = runner.addMonitor(HealthAgentLabActivity::class.java.name, null, false)
        try {
            val join = Intent.makeMainActivity(android.content.ComponentName(ctx, MainActivity::class.java))
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", conversation.id)
            ActivityScenario.launch<MainActivity>(join).use { scenario ->
                var selected = conversation.id
                var needsFreshChat = brief
                val readyBy = SystemClock.elapsedRealtime() + 25_000
                var ready = false
                while (!ready && SystemClock.elapsedRealtime() < readyBy) {
                    scenario.onActivity { a ->
                        ready = a.agentGoalInput.isShown && a.agentGoalInput.hasWindowFocus() &&
                            a.agentRenderedConversationId == selected && a.agentTranscriptWindow.conversationId == selected &&
                            a.ensureCollaborationLoaded(selected) {}
                        if (ready && (needsFreshChat || CollaborationGroupStore.cached(selected) != null)) {
                            require(a.agentInputAttachments.isEmpty() && a.agentGoalInput.text.isNullOrBlank())
                            a.createAgentConversation()
                            selected = a.agentTranscriptStore.activeConversation().id
                            needsFreshChat = false
                            ready = false
                        }
                    }
                    if (!ready) SystemClock.sleep(100)
                }
                assertTrue("Main composer not ready for the selected conversation", ready)
                var submittedAt = 0L
                scenario.onActivity { a ->
                    require(a.agentInputAttachments.isEmpty() && CollaborationGroupStore.cached(selected) == null &&
                        a.agentTranscriptStore.activeConversation().id == selected && a.agentGoalInput.text.isNullOrBlank())
                    val question = if (brief) "体检情况" else "我的体检异常的指标"
                    require(HealthAgentLab.intent(question, false) != null)
                    a.agentGoalInput.setText(question)
                    submittedAt = SystemClock.elapsedRealtime()
                    assertTrue(a.agentSubmitButton.performClick())
                }
                val page = requireNotNull(runner.waitForMonitorWithTimeout(monitor, 15_000)) { "Local results were not opened" }
                try {
                    assertEquals(if (brief) "RESULTS" else "ABNORMAL", page.intent.getStringExtra("mode"))
                    val limit = SystemClock.elapsedRealtime() + 15_000
                    var found = false
                    var blocked = false
                    var empty = false
                    while (!found && SystemClock.elapsedRealtime() < limit) {
                        runner.runOnMainSync {
                            val root = page.window.decorView
                            found = root.findViewWithTag<View>("local-lab-summary")?.isShown == true
                            empty = root.findViewWithTag<View>("local-lab-empty")?.isShown == true
                            val grant = arrayListOf<View>()
                            root.findViewsWithText(grant, ctx.getString(R.string.health_agent_once), View.FIND_VIEWS_WITH_TEXT)
                            blocked = grant.any { it.isShown }
                            if (blocked && InstrumentationRegistry.getArguments().getString("localLabConsentOnce") == "yes")
                                grant.first { it.isShown }.performClick()
                        }
                        if (!found) SystemClock.sleep(80)
                    }
                    assertTrue("No saved measurement summary displayed (consent requested=$blocked, empty=$empty)", found)
                    runner.runOnMainSync {
                        runner.sendStatus(2, android.os.Bundle().apply {
                            putBoolean("local_summary_shown", found)
                            putLong("local_summary_ms", SystemClock.elapsedRealtime() - submittedAt)
                            putBoolean("has_measurement_row", page.window.decorView.findViewWithTag<View>("local-lab-record") != null)
                        })
                    }
                } finally { runner.runOnMainSync { page.finish() } }
            }
        } finally { runner.removeMonitor(monitor) }
    }
}
