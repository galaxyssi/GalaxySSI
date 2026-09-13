package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class AgentConnectorResponseRouterTest {
    private val reply = AgentConnectorResponse(7L, "codex", "result", "conversation", "turn", "task")

    private class Consumer(var rank: Int = 0, var accepted: Boolean = true) : AgentConnectorResponseListener {
        var calls = 0
        override fun priority(response: AgentConnectorResponse) = rank
        override fun onConnectorResponse(response: AgentConnectorResponse): Boolean {
            calls++
            return accepted
        }
    }

    @Test fun pausedTaskOwnerReceivesBeforeForegroundWindow() {
        val router = AgentConnectorResponseRouter()
        val owner = Consumer(2)
        val foreground = Consumer(1)
        router.add(owner)
        router.add(foreground)
        assertTrue(router.dispatch(reply))
        assertEquals(1, owner.calls)
        assertEquals(0, foreground.calls)
    }

    @Test fun tenWindowsOnlyOneConsumerAndRepeatedRegistrationIsIdempotent() {
        val router = AgentConnectorResponseRouter()
        val windows = List(10) { Consumer() }
        windows.forEach(router::add)
        repeat(5) { router.add(windows.last()) }
        assertTrue(router.dispatch(reply))
        assertEquals(1, windows.sumOf { it.calls })
        assertEquals(1, windows.last().calls)
    }

    @Test fun closedOrRejectedOwnerFallsBackToLivePausedWindow() {
        val router = AgentConnectorResponseRouter()
        val paused = Consumer()
        val owner = Consumer(2, accepted = false)
        val closed = Consumer(-1)
        listOf(paused, owner, closed).forEach(router::add)
        assertTrue(router.dispatch(reply))
        assertEquals(1, owner.calls)
        assertEquals(1, paused.calls)
        assertEquals(0, closed.calls)
        router.remove(owner)
        router.remove(paused)
        assertFalse(router.dispatch(reply))
    }

    @Test fun throwingConsumerDoesNotLoseOtherConsumersOrEscapeIntoReceiptPath() {
        val router = AgentConnectorResponseRouter()
        val fallback = Consumer()
        val broken = AgentConnectorResponseListener { error("executor shut down") }
        router.add(fallback)
        router.add(broken)
        assertTrue(router.dispatch(reply))
        assertEquals(1, fallback.calls)
    }

    @Test fun noConsumerOrAllRejectedLeavesDurableInboxForLaterRecovery() {
        val router = AgentConnectorResponseRouter()
        assertFalse(router.dispatch(reply))
        val rejected = Consumer(accepted = false)
        router.add(rejected)
        assertFalse(router.dispatch(reply))
        router.remove(rejected)
        assertFalse(router.dispatch(reply))
        assertEquals(1, rejected.calls)
    }

    @Test fun concurrentArrivalsKeepOneConsumerPerDispatch() {
        val router = AgentConnectorResponseRouter()
        val count = AtomicInteger()
        val windows = List(10) { AgentConnectorResponseListener { count.incrementAndGet(); true } }
        windows.forEach(router::add)
        val executor = Executors.newFixedThreadPool(10)
        try {
            val jobs = (1..100).map { index ->
                executor.submit<Boolean> { router.dispatch(reply.copy(sourceMessageId = index.toLong())) }
            }
            jobs.forEach { assertTrue(it.get()) }
            assertEquals(100, count.get())
        } finally {
            executor.shutdownNow()
        }
    }
}
