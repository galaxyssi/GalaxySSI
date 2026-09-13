package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRunRecorderOwnershipDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val recorder get() = AgentRunRecorder.get(context)

    @Before fun prepare() {
        check(context.packageName == "com.galaxyssi.chat.mqttverification")
        recorder.clear()
    }

    @After fun clean() {
        check(context.packageName == "com.galaxyssi.chat.mqttverification")
        recorder.clear()
    }

    @Test fun windowAndBackgroundContextsShareTheSameRecorderAndFreshIndexes() {
        val window = AgentRunRecorder.get(ContextWrapper(context))
        val background = AgentRunRecorder.get(context.applicationContext)
        assertSame(window, background)
        assertTrue(window.recentRuns().isEmpty())
        val id = conversation()
        assertNull(window.context(id))
        val run = background.begin(id, "Question")
        assertEquals(run, window.activeRun(id))
        finish(background, run)
        assertEquals(AgentRecordedRunStatus.COMPLETED, window.run(run.runId)!!.status)
    }

    @Test fun oldCompletionCannotStealTheCurrentTurnOrItsNextParent() {
        val id = conversation()
        val old = recorder.begin(id, "First")
        val current = recorder.begin(id, "Second")
        val before = recorder.context(id)
        finish(recorder, old)
        assertEquals(before, recorder.context(id))
        assertEquals(current.runId, recorder.activeRun(id)!!.runId)
        val persisted = JSONObject(AgentEncryptedDatabase(context, "galaxyssi_agent_runs_v2")
            .readString("context:$id", ""))
        assertEquals(current.runId, persisted.getString("active_run_id"))
        val next = recorder.begin(id, "Third")
        assertEquals(current.runId, next.parentRunId)
        assertEquals(3, next.revisionNumber)
    }

    @Test fun oldFailureAndCancellationCannotMoveTheCurrentTurn() {
        listOf(AgentRecordedRunStatus.FAILED, AgentRecordedRunStatus.CANCELLED).forEach { status ->
            val id = conversation()
            val old = recorder.begin(id, "Old")
            val current = recorder.begin(id, "Current")
            recorder.reconcileRemoteTerminal(old.runId, status, "Old request ended")
            assertEquals(current.runId, recorder.activeRun(id)!!.runId)
            assertEquals(status, recorder.run(old.runId)!!.status)
        }
    }

    @Test fun interruptedOldRunCannotMoveANewTaskThread() {
        val id = conversation()
        val old = recorder.begin(id, "Old")
        val current = recorder.begin(id, "New thread", forceNewThread = true)
        assertNotEquals(old.taskThreadId, current.taskThreadId)
        recorder.markInterrupted(old.runId, "Old worker ended")
        assertEquals(current.runId, recorder.activeRun(id)!!.runId)
        assertEquals(current.taskThreadId, recorder.context(id)!!.taskThreadId)
        val next = recorder.begin(id, "Continue new thread")
        assertEquals(current.runId, next.parentRunId)
        assertEquals(current.taskThreadId, next.taskThreadId)
        assertEquals(2, next.revisionNumber)
    }

    @Test fun tenConcurrentWindowsInOneConversationProduceOneOrderedParentChain() {
        val id = conversation()
        val runs = concurrent { index -> AgentRunRecorder.get(ContextWrapper(context)).begin(id, "Question $index") }
            .sortedBy(AgentRecordedRun::revisionNumber)
        assertEquals((1..10).toList(), runs.map(AgentRecordedRun::revisionNumber))
        assertEquals(10, runs.map(AgentRecordedRun::runId).distinct().size)
        assertEquals(1, runs.map(AgentRecordedRun::taskThreadId).distinct().size)
        assertEquals("", runs.first().parentRunId)
        runs.zipWithNext().forEach { (parent, child) -> assertEquals(parent.runId, child.parentRunId) }
        runs.asReversed().forEach { finish(recorder, it) }
        assertEquals(runs.last().runId, recorder.activeRun(id)!!.runId)
    }

    @Test fun tenConcurrentConversationsDoNotLoseRunOrContextIndexEntries() {
        val ids = (0 until 10).map { conversation() }
        val runs = concurrent { index -> AgentRunRecorder.get(ContextWrapper(context)).begin(ids[index], "Question $index") }
        assertEquals(runs.map(AgentRecordedRun::runId).toSet(), recorder.recentRuns().map(AgentRecordedRun::runId).toSet())
        runs.forEach { run -> assertEquals(run.runId, recorder.activeRun(run.conversationId)!!.runId) }
        concurrent { index -> finish(AgentRunRecorder.get(context), runs[index]) }
        assertTrue(recorder.runningRuns().isEmpty())
        runs.forEach { run -> assertEquals(run.runId, recorder.activeRun(run.conversationId)!!.runId) }
    }

    @Test fun rebindingAndClearingAreImmediatelyVisibleToAnotherOwner() {
        val first = AgentRunRecorder.get(ContextWrapper(context))
        val second = AgentRunRecorder.get(context)
        val source = conversation()
        val target = conversation()
        val run = first.begin(source, "Question")
        assertNotNull(second.context(source))
        assertEquals(1, first.rebindConversation(source, target))
        assertNull(second.context(source))
        assertEquals(target, second.run(run.runId)!!.conversationId)
        assertEquals(run.runId, second.activeRun(target)!!.runId)
        first.clear()
        assertNull(second.run(run.runId))
        assertNull(second.context(target))
        assertTrue(second.recentRuns().isEmpty())
    }

    private fun conversation(): String = AgentContinuousEvalPolicy.AGENT_LAB_CONVERSATION_PREFIX + UUID.randomUUID()

    private fun finish(recorder: AgentRunRecorder, run: AgentRecordedRun): AgentRecordedRun = checkNotNull(
        recorder.complete(run.runId, "[]", emptyList(), "[]", "{\"text\":\"done\"}", "{}", emptyList()))

    private fun <T> concurrent(block: (Int) -> T): List<T> {
        val executor = Executors.newFixedThreadPool(10)
        val ready = CountDownLatch(10)
        val start = CountDownLatch(1)
        try {
            val tasks = (0 until 10).map { index -> executor.submit<T> {
                ready.countDown()
                check(start.await(10, TimeUnit.SECONDS))
                block(index)
            } }
            check(ready.await(10, TimeUnit.SECONDS))
            start.countDown()
            return tasks.map { it.get(20, TimeUnit.SECONDS) }
        } finally {
            start.countDown()
            executor.shutdownNow()
            check(executor.awaitTermination(10, TimeUnit.SECONDS))
        }
    }
}
