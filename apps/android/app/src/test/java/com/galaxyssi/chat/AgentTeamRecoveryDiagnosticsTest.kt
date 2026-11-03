package com.galaxyssi.chat

import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Test

class AgentTeamRecoveryDiagnosticsTest {
    @Test fun disabledRecorderDoesNoDiagnosticWork() {
        val recorder = TeamRecoveryTraceRecorder(false, clock = { error("Clock must not run") },
            emit = { error("Log must not run") })
        recorder.record("private-run", TeamRecoveryTraceStage.AWAIT_FAILURE, failure = IOException("private"))
        assertEquals(42, recorder.measure("private-run", TeamRecoveryTraceStage.CHECKPOINT_READ) { 42 })
        assertEquals(0, recorder.retainedCounters())
    }

    @Test fun repeatedEventsAreAggregatedWithTimingsAndProgress() {
        var now = 0L
        val lines = mutableListOf<String>()
        val recorder = TeamRecoveryTraceRecorder(true, { now }, lines::add, intervalNanos = 100)
        repeat(20) { recorder.record("run-a", TeamRecoveryTraceStage.RESUME_READY,
            TeamRecoveryTraceSource.WATCH_RELEASE, elapsedNanos = 2_000_000,
            sequence = 31, completedChildren = 4) }
        assertEquals(1, lines.size)
        now = 100
        recorder.record("run-a", TeamRecoveryTraceStage.RESUME_READY, TeamRecoveryTraceSource.WATCH_RELEASE,
            elapsedNanos = 3_000_000, sequence = 32, completedChildren = 4)
        assertEquals(2, lines.size)
        assertTrue(lines.last().contains("count=21 total_ms=43 max_ms=3 sequence=32 completed=4"))
    }

    @Test fun sourcesAndRunsDoNotShareCounters() {
        val lines = mutableListOf<String>()
        val recorder = TeamRecoveryTraceRecorder(true, { 0 }, lines::add)
        recorder.record("run-a", TeamRecoveryTraceStage.RESUME_ATTEMPT, TeamRecoveryTraceSource.PERIODIC)
        recorder.record("run-a", TeamRecoveryTraceStage.RESUME_ATTEMPT, TeamRecoveryTraceSource.WATCH_RELEASE)
        recorder.record("run-b", TeamRecoveryTraceStage.RESUME_ATTEMPT, TeamRecoveryTraceSource.WATCH_RELEASE)
        assertEquals(3, lines.size)
        assertTrue(lines.all { it.contains("count=1 ") })
        assertNotEquals(lines[1].substringBefore(' '), lines[2].substringBefore(' '))
    }

    @Test fun nestedFailureSitesAreVisibleWithoutPrivateMessagesOrRunIds() {
        val lines = mutableListOf<String>()
        val recorder = TeamRecoveryTraceRecorder(true, { 0 }, lines::add)
        val cause = IOException("private user goal, bearer token and checkpoint body")
        cause.stackTrace = arrayOf(StackTraceElement("com.galaxyssi.chat.ExampleStore", "write", "ExampleStore.kt", 37))
        val failure = CancellationException("private cancellation").apply { initCause(cause) }
        recorder.record("private-run-identity", TeamRecoveryTraceStage.AWAIT_FAILURE, failure = failure)
        val line = lines.single()
        assertTrue(line.contains("CancellationException["))
        assertTrue(line.contains("IOException[com.galaxyssi.chat.ExampleStore.write:37]"))
        assertFalse(line.contains("private"))
        assertFalse(line.contains("bearer"))
        assertFalse(line.contains("checkpoint body"))
    }

    @Test fun changedFailureIsNotHiddenByAggregationAndCyclicCausesTerminate() {
        val lines = mutableListOf<String>()
        val recorder = TeamRecoveryTraceRecorder(true, { 0 }, lines::add)
        val first = IOException("secret")
        val second = IllegalStateException("secret")
        first.initCause(second)
        second.initCause(first)
        recorder.record("run", TeamRecoveryTraceStage.AWAIT_FAILURE, failure = first)
        recorder.record("run", TeamRecoveryTraceStage.AWAIT_FAILURE, failure = first)
        recorder.record("run", TeamRecoveryTraceStage.AWAIT_FAILURE, failure = UnsupportedOperationException())
        assertEquals(2, lines.size)
        assertTrue(lines.last().contains("count=3"))
    }

    @Test fun loggingFailureCannotChangeResultOrOriginalException() {
        var now = 0L
        val recorder = TeamRecoveryTraceRecorder(true, { now++ }, { error("Logger failed") })
        assertEquals("result", recorder.measure("run", TeamRecoveryTraceStage.CHECKPOINT_READ) { "result" })
        val failure = IOException("original")
        assertSame(failure, runCatching {
            recorder.measure("run", TeamRecoveryTraceStage.CHECKPOINT_WRITE) { throw failure }
        }.exceptionOrNull())
        val brokenClock = TeamRecoveryTraceRecorder(true, { error("Clock failed") }, { error("Sink failed") })
        assertEquals(42, brokenClock.measure("run", TeamRecoveryTraceStage.CHECKPOINT_READ) { 42 })
    }

    @Test fun metadataRetentionIsBounded() {
        val recorder = TeamRecoveryTraceRecorder(true, { 0 }, {}, capacity = 3)
        repeat(100) { recorder.record("run-$it", TeamRecoveryTraceStage.INTERRUPTED) }
        assertEquals(3, recorder.retainedCounters())
    }

    @Test fun concurrentEventsDoNotLoseAggregateCounts() {
        var now = 0L
        val lines = mutableListOf<String>()
        val recorder = TeamRecoveryTraceRecorder(true, { now }, { synchronized(lines) { lines.add(it) }; Unit },
            intervalNanos = 100)
        val executor = Executors.newFixedThreadPool(4)
        try {
            val tasks = (1..100).map { executor.submit {
                recorder.record("run", TeamRecoveryTraceStage.CHECKPOINT_READ)
            } }
            tasks.forEach { it.get(5, TimeUnit.SECONDS) }
        } finally { executor.shutdownNow() }
        now = 100
        recorder.record("run", TeamRecoveryTraceStage.CHECKPOINT_READ)
        assertEquals(2, lines.size)
        assertTrue(lines.last().contains("count=101"))
    }
}
