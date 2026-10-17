package com.galaxyssi.chat

import java.util.concurrent.Executor
import org.junit.Assert.*
import org.junit.Test

class AgentForegroundReloadTest {
    private class Queue : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) { tasks.add(command) }
        fun drain() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }

    @Test fun requestNeverLoadsOnTheCallingThread() {
        val worker = Queue(); val ui = Queue()
        val reload = AgentForegroundReload<Int>(worker, ui)
        var loads = 0; var displayed = 0
        reload.request({ loads++; 42 }, { displayed = it.getOrThrow() })
        assertEquals(0, loads)
        worker.drain()
        assertEquals(0, displayed)
        ui.drain()
        assertEquals(42, displayed)
    }

    @Test fun pauseOrConversationChangeDropsQueuedPlaintext() {
        val worker = Queue(); val ui = Queue()
        val reload = AgentForegroundReload<String>(worker, ui)
        var delivered = false
        reload.request({ "old conversation" }, { delivered = true })
        worker.drain()
        reload.invalidate()
        ui.drain()
        assertFalse(delivered)
    }

    @Test fun repeatedResumesCoalesceAndOnlyNewestSnapshotIsRendered() {
        val worker = Queue(); val ui = Queue()
        val reload = AgentForegroundReload<Int>(worker, ui)
        val values = mutableListOf<Int>(); var loads = 0
        repeat(100) { value -> reload.request({ loads++; value }, { values += it.getOrThrow() }) }
        assertEquals(1, worker.tasks.size)
        worker.drain(); ui.drain()
        assertEquals(1, loads)
        assertEquals(listOf(99), values)
    }

    @Test fun newResumeWhileLoadingInvalidatesOldResultAndRunsOnceMore() {
        val worker = Queue(); val ui = Queue()
        val reload = AgentForegroundReload<Int>(worker, ui)
        val values = mutableListOf<Int>()
        reload.request({ current ->
            assertTrue(current())
            reload.request({ 2 }, { values += it.getOrThrow() })
            assertFalse(current())
            1
        }, { values += it.getOrThrow() })
        worker.drain(); ui.drain()
        assertEquals(listOf(2), values)
    }

    @Test fun aFailedLoadDoesNotPreventTheNextResume() {
        val worker = Queue(); val ui = Queue()
        val reload = AgentForegroundReload<Int>(worker, ui)
        val results = mutableListOf<Result<Int>>()
        reload.request({ error("fixture") }, { results += it })
        worker.drain(); ui.drain()
        reload.request({ 2 }, { results += it })
        worker.drain(); ui.drain()
        assertTrue(results[0].isFailure)
        assertEquals(2, results[1].getOrThrow())
    }
}
