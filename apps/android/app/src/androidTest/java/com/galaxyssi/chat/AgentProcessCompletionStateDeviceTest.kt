package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentProcessCompletionStateDeviceTest {
    private fun process() = UUID.randomUUID().toString().let { id ->
        AgentTranscriptEntry("event-$id", AgentTranscriptRole.PROCESS, "Waiting for reply",
            System.currentTimeMillis() - 5000, conversationId = "conversation-$id", turnId = "turn-$id", taskId = "task-$id")
    }

    private fun waiting(activity: MainActivity, entry: AgentTranscriptEntry) {
        activity.renderedAgentTranscriptSourceEntries = listOf(entry)
        activity.agentExecutionPresentations[entry.taskId] = AgentExecutionPresentation(
            executorId = "codex", executorLabel = "Codex", locationKind = AgentExecutionLocationKind.DESKTOP,
            locationLabelHint = "Desktop", currentStep = "Waiting", phase = AgentPhase.WAITING_RESPONSE,
            cancellable = true, startedAtMillis = entry.timestampMillis)
    }

    private fun lookup(entry: AgentTranscriptEntry, status: AgentWorkspaceStatus, revision: Long) =
        AgentProcessCompletionLookup((entry.timestampMillis + 4000).takeIf { status.isTerminal },
            SystemClock.elapsedRealtime(), status, entry.timestampMillis, entry.conversationId, revision)

    @Test fun committedCompletionStopsAttachedClockAndProgressDespiteStaleWaitingProjection() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            awaitHydration(scenario)
            val entry = process()
            lateinit var row: View
            lateinit var expected: String
            scenario.onActivity { activity ->
                waiting(activity, entry)
                row = activity.agentProcessTranscriptRow(entry)
                activity.findViewById<ViewGroup>(android.R.id.content).addView(row)
                activity.applyAgentProcessCompletionLookup(entry.conversationId, entry.turnId,
                    lookup(entry, AgentWorkspaceStatus.COMPLETED, 12))
                assertFalse(activity.agentProcessIsRunning(entry))
                assertEquals(AgentPhase.COMPLETED, activity.agentProcessPhase(entry))
                expected = activity.getString(R.string.agent_trace_processed, activity.agentProcessedDuration(4000), "").trimEnd()
                val presentation = AgentInteractiveProgressPolicy.project("Test", null, activity.agentProcessPhase(entry),
                    listOf("Plan", "Wait for reply", "Verify result"), completed = true, fallbackPhase = AgentPhase.WAITING_RESPONSE)
                assertEquals(AgentInteractiveProgressStatus.COMPLETED, presentation.status)
                assertFalse(presentation.running)
            }
            Thread.sleep(1300)
            scenario.onActivity { activity ->
                assertEquals(expected, texts(row).first().text.toString())
                activity.applyAgentProcessCompletionLookup(entry.conversationId, entry.turnId,
                    lookup(entry, AgentWorkspaceStatus.WAITING_RESPONSE, 11))
                assertFalse(activity.agentProcessIsRunning(entry))
            }
            Thread.sleep(1300)
            scenario.onActivity { activity ->
                assertEquals(expected, texts(row).first().text.toString())
                (row.parent as ViewGroup).removeView(row)
                activity.agentExecutionPresentations.remove(entry.taskId)
                activity.agentProcessCompletionLookups.remove(entry.turnId)
            }
        }
    }

    @Test fun aCompletedAttemptAndInterimReplyDoNotFinishAnActiveTurn() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            awaitHydration(scenario)
            scenario.onActivity { activity ->
            val entry = process()
            waiting(activity, entry)
            val done = activity.agentExecutionPresentations.getValue(entry.taskId).copy(
                phase = AgentPhase.COMPLETED, cancellable = false, completedAtMillis = entry.timestampMillis + 2000)
            activity.agentExecutionPresentations[entry.taskId] = done
            activity.applyAgentProcessCompletionLookup(entry.conversationId, entry.turnId,
                lookup(entry, AgentWorkspaceStatus.RUNNING, 10))
            val interim = entry.copy(role = AgentTranscriptRole.ASSISTANT, text = "First step complete")
            assertNull(activity.agentProcessCompletionTimestamp(entry, listOf(entry, interim)))
            assertTrue(activity.agentProcessIsRunning(entry))
            activity.applyAgentProcessCompletionLookup("other", entry.turnId, lookup(entry, AgentWorkspaceStatus.COMPLETED, 11))
            assertTrue(activity.agentProcessIsRunning(entry))
            activity.applyAgentProcessCompletionLookup(entry.conversationId, entry.turnId,
                lookup(entry, AgentWorkspaceStatus.FAILED, 12))
            assertFalse(activity.agentProcessIsRunning(entry))
            activity.applyAgentProcessCompletionLookup(entry.conversationId, entry.turnId,
                lookup(entry, AgentWorkspaceStatus.WAITING_RESPONSE, 13))
            assertTrue(activity.agentProcessIsRunning(entry))
            activity.agentExecutionPresentations.remove(entry.taskId)
            activity.agentProcessCompletionLookups.remove(entry.turnId)
        } }
    }

    @Test fun persistedStatusChangeRefreshesOnlyTheCollapsedProcessRow() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val entry = process()
        val database = "test-process-state-${UUID.randomUUID()}"
        val store = EncryptedAgentWorkspaceStore(context, database)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            awaitHydration(scenario)
            val changed = mutableListOf<Pair<Int, Int>>()
            val observer = object : RecyclerView.AdapterDataObserver() {
                override fun onItemRangeChanged(positionStart: Int, itemCount: Int, payload: Any?) {
                    changed += positionStart to itemCount
                }
            }
            scenario.onActivity { activity ->
                waiting(activity, entry)
                val other = process()
                activity.renderedAgentTranscriptSourceEntries = listOf(entry, other)
                val groups = AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(entry, other))
                activity.agentTranscriptAdapter.replaceAll(groups)
                activity.agentTranscriptAdapter.registerAdapterDataObserver(observer)
            }
            try {
                store.upsert(AgentWorkspace(entry.turnId, entry.taskId, entry.conversationId, entry.taskId,
                    status = AgentWorkspaceStatus.COMPLETED, createdAtMillis = entry.timestampMillis,
                    updatedAtMillis = entry.timestampMillis + 4000))
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals("Committed workspace must refresh only its collapsed row", listOf(0 to 1), changed)
                    assertFalse(activity.agentProcessIsRunning(entry))
                }
            } finally {
                scenario.onActivity { activity ->
                    activity.agentTranscriptAdapter.unregisterAdapterDataObserver(observer)
                    activity.agentExecutionPresentations.remove(entry.taskId)
                    activity.agentProcessCompletionLookups.remove(entry.turnId)
                }
                store.clear()
                context.deleteDatabase("$database.db")
            }
        }
    }

    @Test fun inspectExistingCompletedTurnWithoutChangingItsData() {
        val args = InstrumentationRegistry.getArguments()
        val conversation = args.getString("process_conversation").orEmpty()
        val turn = args.getString("process_turn").orEmpty()
        assumeTrue(conversation.isNotBlank() && turn.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val entries = AgentTranscriptStore(context).entriesForTurn(turn).filter { it.conversationId == conversation }
        val entry = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries).first { it.role == AgentTranscriptRole.PROCESS }
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            awaitHydration(scenario)
            scenario.onActivity { activity ->
                waiting(activity, entry)
                activity.renderedAgentTranscriptSourceEntries = entries
                activity.agentProcessCompletionLookups.remove(turn)
                assertNull(activity.agentProcessCompletionTimestamp(entry, entries))
            }
            val deadline = SystemClock.elapsedRealtime() + 15000
            var completed: Long? = null
            while (completed == null && SystemClock.elapsedRealtime() < deadline) {
                Thread.sleep(100)
                scenario.onActivity { completed = it.agentProcessCompletionTimestamp(entry, entries) }
            }
            assertNotNull("A stale waiting projection must not prevent the indexed workspace lookup", completed)
            scenario.onActivity { activity ->
                assertEquals(AgentPhase.COMPLETED, activity.agentProcessPhase(entry))
                val row = activity.agentProcessTranscriptRow(entry)
                activity.findViewById<ViewGroup>(android.R.id.content).addView(row)
                assertTrue(texts(row).first().text.toString().startsWith(activity.getString(R.string.agent_trace_processed, "", "").trim()))
                (row.parent as ViewGroup).removeView(row)
            }
        }
    }

    private fun awaitHydration(scenario: ActivityScenario<MainActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { ready = !it.initialAgentHydrationPending && !it.runtimePlaintextCleared }
            if (!ready) Thread.sleep(50)
        }
        assertTrue("Initial transcript hydration must finish before injecting the isolated fixture", ready)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun texts(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
        else -> emptyList()
    }
}
