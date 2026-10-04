package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConversationTaskIsolationDeviceTest {
    @Test fun restoredWaitingTeamKeepsReceiptAcrossResume() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = "test-team-${UUID.randomUUID()}"
        val action = AgentAction("dispatch", AgentActionKind.CALL_CONNECTOR, "Team", AgentRisk.LOW,
            AgentActionStatus.WAITING_RESPONSE, "Await reply", requiresConfirmation = false)
        val receipt = AgentActionResult("dispatch", false, "Waiting", mapOf(
            "team_run_id" to run, "resource_location" to "distributed",
            "source_message_id" to AgentTeamDispatchIds.sourceMessageId(run).toString()))
        val store = InMemoryAgentSessionStore().apply {
            save(AgentSessionSnapshot(run, AgentPhase.WAITING_RESPONSE, "Test", ScreenContext("", pageTitle = ""),
                AgentPlan("Test", ScreenContext("", pageTitle = ""), emptyList(), listOf(action), confirmationRequired = false),
                emptyList(), receipt, updatedAtMillis = 1, processInstanceId = "previous-process",
                executionLoopSnapshot = AgentExecutionLoop.create { 1 }.apply {
                    start(run, AgentExecutionLoopBudget())
                }.snapshot!!.copy(phase = AgentExecutionLoopPhase.OBSERVE, lastActionId = action.id)))
        }
        val runtime = MobileNativeAgent(context, sessionStore = store)
        assertEquals(AgentPhase.WAITING_RESPONSE, runtime.phase)
        assertEquals(receipt, runtime.lastActionResult)
        runtime.phase = AgentPhase.PAUSED
        runtime.resumeCurrentTask()
        assertEquals(AgentPhase.WAITING_RESPONSE, runtime.phase)
        assertEquals(receipt, runtime.lastActionResult)
        assertEquals(AgentActionStatus.WAITING_RESPONSE, runtime.currentPlan!!.actions.single().status)
    }

    @Test fun newConversationDoesNotClearDisplayedTaskCheckpoint() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val token = "task-isolation-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context, token)
        val original = transcript.createConversation(privateMode = true)
        val tasks = SharedPreferencesAgentSessionStore(context, "task:$token")
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var activity: MainActivity? = null
        var created: String? = null
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$token"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, token)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            activity = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Test window did not open")
            val page = requireNotNull(activity)
            val deadline = SystemClock.elapsedRealtime() + 30_000
            while (page.initialAgentHydrationPending && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
            assertFalse(page.initialAgentHydrationPending)
            val taskRuntime = MobileNativeAgent(context, sessionStore = tasks)
            taskRuntime.currentGoal = "Preserved background task"
            taskRuntime.phase = AgentPhase.WAITING_RESPONSE
            taskRuntime.lastActionResult = AgentActionResult("original", false, "Waiting", mapOf("team_run_id" to token))
            taskRuntime.persistSession()
            val before = tasks.load()!!
            instrumentation.runOnMainSync {
                page.mobileNativeAgent = taskRuntime
                page.createAgentConversation()
                created = page.agentTranscriptStore.activeConversation().id
                assertNotSame(taskRuntime, page.mobileNativeAgent)
                assertEquals("window:$token", (page.mobileNativeAgent.sessionStore as SharedPreferencesAgentSessionStore).storageKey)
                assertEquals("", page.mobileNativeAgent.currentGoal)
            }
            assertEquals(before, tasks.load())
            assertEquals(AgentPhase.WAITING_RESPONSE, taskRuntime.phase)
            assertEquals("Preserved background task", taskRuntime.currentGoal)
            assertFalse(tasks.restoreIfUnchanged(before.copy(updatedAtMillis = -1), before.copy(currentGoal = "Wrong")))
            assertEquals(before, tasks.load())
        } finally {
            instrumentation.runOnMainSync { activity?.finishAndRemoveTask() }
            tasks.clear()
            SharedPreferencesAgentSessionStore(context, "window:$token").clear()
            listOfNotNull(original.id, created).forEach(transcript::deleteConversation)
            instrumentation.removeMonitor(monitor)
        }
    }
}
