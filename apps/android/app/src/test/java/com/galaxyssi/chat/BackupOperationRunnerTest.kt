package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException

class BackupOperationRunnerTest {
    @Test fun workDoesNotRunOnSubmissionAndDuplicateIsRejected() {
        val queue = ArrayDeque<Runnable>()
        val runner = BackupOperationRunner(Executor(queue::addLast))
        var worked = false
        var completed = false
        assertTrue(runner.submit({ worked = true }, { assertTrue(it.isSuccess); completed = true }))
        assertFalse(worked)
        assertFalse(runner.submit({ fail("Duplicate ran") }, { fail("Duplicate callback") }))
        queue.removeFirst().run()
        assertTrue(worked); assertTrue(completed)
        assertTrue(runner.submit({}, {}))
    }

    @Test fun failureReleasesTheSlotAndReportsTheOriginalCause() {
        val runner = BackupOperationRunner(Executor(Runnable::run))
        val failure = IllegalStateException("fixture failure")
        runner.submit({ throw failure }, { assertSame(failure, it.exceptionOrNull()) })
        assertTrue(runner.submit({}, { assertTrue(it.isSuccess) }))
    }

    @Test fun executorRejectionDoesNotLeaveTheSlotStuck() {
        var reject = true
        val runner = BackupOperationRunner(Executor { if (reject) throw RejectedExecutionException() else it.run() })
        var failure: Throwable? = null
        assertTrue(runner.submit({}, { failure = it.exceptionOrNull() }))
        assertTrue(failure is RejectedExecutionException)
        reject = false
        assertTrue(runner.submit({}, {}))
    }
}
