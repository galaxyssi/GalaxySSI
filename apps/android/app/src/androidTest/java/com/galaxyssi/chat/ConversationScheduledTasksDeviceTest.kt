package com.galaxyssi.chat

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated synthetic schedules. No model dispatch, contact action, or external app launch. */
@RunWith(AndroidJUnit4::class)
class ConversationScheduledTasksDeviceTest {
    @Test fun speechReadsTheVisibleCardAfterLiveStatusChanges() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val root = android.widget.LinearLayout(context)
            val status = ConversationScheduleStatusView(context, "speech-fixture", includeSchedule = true,
                cardTitle = "Open clock").apply { text = "Every minute" }
            root.addView(status)
            assertEquals("Open clock\nEvery minute", ConversationScheduleCardPresentation.visibleSpeechText(root))
            status.text = "Every minute - Paused"
            assertEquals("Open clock\nEvery minute - Paused", ConversationScheduleCardPresentation.visibleSpeechText(root))
            status.text = context.getString(R.string.schedule_not_found)
            assertEquals("Open clock\n${status.text}", ConversationScheduleCardPresentation.visibleSpeechText(root))
            status.visibility = android.view.View.GONE
            assertNull(ConversationScheduleCardPresentation.visibleSpeechText(root))
        }
    }

    @Test fun editPauseResumeAndReloadPreserveIdentity() = isolated { context ->
        val first = ConversationScheduledTasks.save(context, "fixture-conversation", command("Check A"))
        val second = ConversationScheduledTasks.save(context, "fixture-conversation", command("Check A and B"), first.taskId)
        assertEquals(first.taskId, second.taskId)
        assertEquals(1, ConversationScheduledTasks.tasks(context).size)
        assertEquals("Check A and B", AgentProactiveTaskStore(context).task(first.taskId)?.action?.prompt)
        val repeated = ConversationScheduledTasks.save(context, "fixture-conversation", command("Check B"))
        assertEquals(first.taskId, repeated.taskId)
        ConversationScheduledTasks.setEnabled(context, first.taskId, false)
        assertFalse(requireNotNull(AgentProactiveTaskStore(context).task(first.taskId)).enabled)
        val launchesBeforePausedAlarm = context.launches
        AgentProactiveTaskScheduler.handleAlarm(context, first.taskId)
        assertEquals(launchesBeforePausedAlarm, context.launches)
        ConversationScheduledTasks.setEnabled(context, first.taskId, true)
        assertTrue(requireNotNull(AgentProactiveTaskStore(context).task(first.taskId)).enabled)
    }

    @Test fun missedOccurrencesCoalesceWhileOneRunIsPending() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check"))
        val store = AgentProactiveTaskStore(context)
        repeat(4) {
            store.upsert(requireNotNull(store.task(task.taskId)).copy(nextRunAtMillis = System.currentTimeMillis() - 60_000))
            AgentProactiveTaskScheduler.handleAlarm(context, task.taskId)
        }
        assertEquals(1, store.runs(task.taskId).count { !it.status.terminal })
        assertTrue(context.launches > 0)
    }

    @Test fun completionIsAtomicAndDuplicateDeliveryIsIdempotent() = isolated { context ->
        val transcript = AgentTranscriptStore(context)
        val conversation = transcript.createConversation("Schedule fixture")
        transcript.append(AgentTranscriptRole.USER, "Fixture", conversationId = conversation.id)
        val task = ConversationScheduledTasks.save(context, conversation.id, command("Check"))
        val store = AgentProactiveTaskStore(context)
        val run = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, System.currentTimeMillis(), AgentProactiveRunStatus.RUNNING)
        assertTrue(store.createRun(run))
        val result = run.copy(status = AgentProactiveRunStatus.COMPLETED, completedAtMillis = System.currentTimeMillis(),
            resultSummary = "Verified synthetic output")
        assertTrue(store.completeScheduledRun(result))
        assertFalse(store.completeScheduledRun(result))
        assertEquals(1, store.task(task.taskId)?.runCount)
        assertTrue(ConversationScheduledTasks.deliver(context, task, result))
        assertFalse(ConversationScheduledTasks.deliver(context, task, result))
        assertTrue(requireNotNull(store.run(run.runId)).deliveryRecorded)
        assertEquals(1, transcript.list(conversation.id).count { it.dedupeKey == "scheduled-result:${run.runId}" })
    }

    @Test fun taskScopeCannotBeChangedByEditingAnotherConversation() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "first", command("Check"))
        assertTrue(runCatching { ConversationScheduledTasks.save(context, "second", command("Changed"), task.taskId) }.isFailure)
        assertEquals("Check", AgentProactiveTaskStore(context).task(task.taskId)?.action?.prompt)
    }

    @Test fun pauseCancelsPendingRunAndLateResultCannotReviveIt() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check"))
        val store = AgentProactiveTaskStore(context)
        val run = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, 1L, AgentProactiveRunStatus.QUEUED)
        store.createRun(run)
        ConversationScheduledTasks.setEnabled(context, task.taskId, false)
        assertEquals(AgentProactiveRunStatus.CANCELLED, store.run(run.runId)?.status)
        assertFalse(store.completeScheduledRun(run.copy(status = AgentProactiveRunStatus.COMPLETED)))
        assertFalse(store.updateScheduledPendingRun(run.copy(status = AgentProactiveRunStatus.RUNNING)))
        assertFalse(requireNotNull(store.task(task.taskId)).enabled)
    }

    @Test fun explicitScheduleIsNotBlockedByUnrelatedForegroundWork() = isolated { context ->
        val conversation = AgentTranscriptStore(context).createConversation("Local schedule fixture")
        val task = ConversationScheduledTasks.save(context, conversation.id, command("open alarms"))
        val store = AgentProactiveTaskStore(context)
        store.upsert(task.copy(action = task.action.copy(deliveryMode = "store")))
        val run = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, System.currentTimeMillis(), AgentProactiveRunStatus.QUEUED)
        store.createRun(run)
        AgentForegroundWorkCoordinator.begin("unrelated-${UUID.randomUUID()}").use {
            AgentProactiveTaskExecutor.execute(context, run.runId)
        }
        val result = requireNotNull(store.run(run.runId))
        assertTrue(result.status.terminal)
        assertTrue(result.teamRunId.isBlank())
        assertFalse(result.resultSummary.contains("Waiting for foreground"))
        val launches = context.activityLaunches
        AgentProactiveTaskExecutor.execute(context, run.runId)
        assertEquals(launches, context.activityLaunches)
    }

    @Test fun unverifiedResultSurvivesReloadAndDoesNotHideLaterSuccess() = isolated { context ->
        val transcript = AgentTranscriptStore(context)
        val conversation = transcript.createConversation("Outcome fixture")
        val task = ConversationScheduledTasks.save(context, conversation.id, command("Check"))
        val store = AgentProactiveTaskStore(context)
        val first = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, 1L, AgentProactiveRunStatus.RUNNING)
        store.createRun(first)
        val uncertain = first.copy(status = AgentProactiveRunStatus.UNVERIFIED, completedAtMillis = 2L, resultSummary = "Observation")
        assertTrue(store.completeScheduledRun(uncertain))
        assertEquals(AgentProactiveRunStatus.UNVERIFIED, AgentProactiveTaskStore(context).run(first.runId)?.status)
        assertTrue(ConversationScheduledTasks.deliver(context, task, uncertain))
        val second = first.copy(runId = UUID.randomUUID().toString(), scheduledForMillis = 3L)
        store.createRun(second)
        val confirmed = second.copy(status = AgentProactiveRunStatus.COMPLETED, completedAtMillis = 4L, resultSummary = "Observation")
        assertTrue(store.completeScheduledRun(confirmed))
        assertTrue(ConversationScheduledTasks.deliver(context, task, confirmed))
        assertEquals(2, transcript.list(conversation.id).count { it.dedupeKey.startsWith("scheduled-result:") })
    }

    @Test fun resumedScheduleShowsPendingInsteadOfLastCancellation() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check"))
        val old = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, 1L,
            AgentProactiveRunStatus.CANCELLED, resultSummary = "Proactive task cancelled")
        val text = ConversationScheduleState.text(context, task, old)
        assertTrue(text.contains(context.getString(R.string.schedule_pending)))
        assertEquals(task.action.scheduleText, ConversationScheduleState.text(context, task, old, includeSchedule = true))
        assertFalse(text.contains("Proactive task cancelled"))
        assertFalse(text.contains(context.getString(R.string.schedule_paused)))
        val paused = ConversationScheduleState.text(context, task.copy(enabled = false), old)
        assertEquals(context.getString(R.string.schedule_paused), paused)
    }

    @Test fun updatedScheduleDoesNotPresentPreviousRevisionFailureAsCurrent() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check"))
        val old = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, 1L,
            AgentProactiveRunStatus.FAILED, causeJson = "{\"task_revision\":${task.revision}}",
            resultSummary = "Old failure")
        assertTrue(ConversationScheduleState.text(context, task.copy(revision = task.revision + 1), old)
            .contains(context.getString(R.string.schedule_pending)))
        val completed = old.copy(status = AgentProactiveRunStatus.COMPLETED)
        assertTrue(ConversationScheduleState.text(context, task, completed).contains(
            context.getString(R.string.schedule_last_execution, context.getString(R.string.automation_run_status_completed))))
    }

    @Test fun savingQueuesFirstOccurrenceImmediatelyAndDoesNotRepeatItOnRestore() = isolated { context ->
        val before = System.currentTimeMillis()
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check").copy(
            trigger = AgentProactiveTrigger(AgentProactiveTriggerKind.INTERVAL, intervalSeconds = 60)))
        val after = System.currentTimeMillis()
        val store = AgentProactiveTaskStore(context)
        val first = store.runs(task.taskId).single()
        assertEquals(AgentProactiveRunStatus.QUEUED, first.status)
        assertTrue(first.scheduledForMillis in before..after)
        assertEquals(first.scheduledForMillis + 60_000L, task.nextRunAtMillis)
        assertEquals(1, context.launches)
        AgentProactiveTaskScheduler.handleAlarm(context, task.taskId)
        assertEquals(1, context.launches)
        assertTrue(store.completeScheduledRun(first.copy(status = AgentProactiveRunStatus.COMPLETED,
            completedAtMillis = after, resultSummary = "Synthetic result", deliveryRecorded = true)))
        AgentProactiveTaskScheduler.restoreAll(context, conversationOnly = true)
        assertEquals(1, store.runs(task.taskId).size)
        assertEquals(1, context.launches)
        assertEquals(task.nextRunAtMillis, store.task(task.taskId)?.nextRunAtMillis)
    }

    @Test fun immediateCronOccurrencePreservesNextCalendarTime() = isolated { context ->
        val trigger = AgentProactiveTrigger(AgentProactiveTriggerKind.CRON, cron = "0 9 * * *")
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check").copy(trigger = trigger))
        val first = AgentProactiveTaskStore(context).runs(task.taskId).single()
        assertEquals(AgentCronExpression.parse(trigger.cron).nextAfter(first.scheduledForMillis, trigger.timeZone),
            task.nextRunAtMillis)
        assertEquals(1, context.launches)
    }

    @Test fun compactCardOnlyShowsFrequencyAndPauseState() = isolated { context ->
        val task = ConversationScheduledTasks.save(context, "fixture", command("Check"))
        val run = AgentProactiveRun(UUID.randomUUID().toString(), task.taskId, 1L,
            AgentProactiveRunStatus.UNVERIFIED, resultSummary = "Internal diagnostic")
        assertEquals(task.action.scheduleText, ConversationScheduleState.text(context, task, run, includeSchedule = true))
        val paused = ConversationScheduleState.text(context, task.copy(enabled = false), run, includeSchedule = true)
        assertTrue(paused.contains(context.getString(R.string.schedule_paused)))
        assertFalse(paused.contains("Internal diagnostic"))
        val blocks = AgentRichContentCodec.decode(ConversationScheduledTasks.richCard(context, task))
        assertEquals(1, blocks.size)
        assertEquals(AgentRichBlockType.ACTIONS, blocks.single().type)
    }

    @Test fun localObservationDiagnosticsRemainStoredWithoutChatDelivery() = isolated { context ->
        val transcript = AgentTranscriptStore(context)
        val conversation = transcript.createConversation("Quiet schedule fixture")
        val task = ConversationScheduledTasks.save(context, conversation.id, command("Check"))
        val store = AgentProactiveTaskStore(context)
        val first = store.runs(task.taskId).single()
        val result = first.copy(status = AgentProactiveRunStatus.UNVERIFIED,
            completedAtMillis = System.currentTimeMillis(), errorCode = "foreground_observer_unavailable",
            resultSummary = context.getString(R.string.schedule_local_unverified))
        assertTrue(store.completeScheduledRun(result))
        assertFalse(ConversationScheduledTasks.deliver(context, task, result))
        val retained = requireNotNull(store.run(first.runId))
        assertTrue(retained.deliveryRecorded)
        assertEquals(result.resultSummary, retained.resultSummary)
        assertEquals(AgentProactiveRunStatus.UNVERIFIED, retained.status)
        assertFalse(transcript.list(conversation.id).any { it.dedupeKey == "scheduled-result:${first.runId}" })
    }

    @Test fun legacyNoiseFilterDoesNotHideUserTextOrUsefulResults() = isolated { context ->
        val entry = AgentTranscriptEntry("fixture", AgentTranscriptRole.ASSISTANT,
            context.getString(R.string.schedule_unverified_result, "Check",
                context.getString(R.string.schedule_local_unverified)), 1L, dedupeKey = "scheduled-result:fixture")
        assertTrue(ConversationScheduledTasks.isQuietLegacyStatus(context, entry))
        assertFalse(ConversationScheduledTasks.isQuietLegacyStatus(context, entry.copy(dedupeKey = "")))
        assertFalse(ConversationScheduledTasks.isQuietLegacyStatus(context, entry.copy(role = AgentTranscriptRole.USER)))
        assertFalse(ConversationScheduledTasks.isQuietLegacyStatus(context, entry.copy(text = "Useful research result")))
    }

    private fun command(prompt: String) = ConversationScheduleCommand(ConversationScheduleOperation.SAVE, prompt,
        AgentProactiveTrigger(AgentProactiveTriggerKind.INTERVAL, intervalSeconds = 86400), "Every day")

    private fun isolated(block: (IsolatedContext) -> Unit) {
        val context = IsolatedContext(InstrumentationRegistry.getInstrumentation().targetContext)
        try { block(context) } finally {
            ConversationScheduledTasks.tasks(context).forEach { AgentProactiveTaskScheduler.cancel(context, it.taskId) }
            context.cleanup()
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "schedule-test-${UUID.randomUUID()}-"
        private val databases = ConcurrentHashMap.newKeySet<String>()
        private val preferences = ConcurrentHashMap.newKeySet<String>()
        var launches = 0
        var activityLaunches = 0
        override fun getApplicationContext(): Context = this
        override fun startActivity(intent: Intent) { activityLaunches++ }
        override fun startForegroundService(service: Intent): ComponentName? { launches++; return null }
        override fun startService(service: Intent): ComponentName? { launches++; return null }
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            databases.add(prefix + name); baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, handler)
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            preferences.add(prefix + name); return baseContext.getSharedPreferences(prefix + name, mode)
        }
        fun cleanup() {
            // Global transcript callbacks outlive each fixture and keep database handles open.
            // The device harness removes these names after the instrumentation process exits.
            println("SCHEDULE_FIXTURE_CLEANUP_PREFIX=$prefix")
        }
    }
}
