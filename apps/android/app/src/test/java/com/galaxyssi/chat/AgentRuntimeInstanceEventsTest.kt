package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeInstanceEventsTest {
    private val queue = mutableListOf<() -> Unit>()
    private val events = AgentRuntimeInstanceEventHub(queue::add)
    private val seen = mutableListOf<AgentRuntimeInstanceEvent>()
    private fun drain() { while (queue.isNotEmpty()) queue.removeAt(0).invoke() }

    @Test fun exitIsOneShotAndDoesNotRunListenersOnTheMonitorThread() {
        events.started("one")
        events.observe("one", seen::add)
        assertTrue(queue.isEmpty())
        events.exited("one")
        events.exited("one")
        assertTrue(seen.isEmpty())
        drain()
        assertEquals(listOf(AgentRuntimeInstanceEvent("one", AgentRuntimeInstanceEvent.Kind.EXITED)), seen)
    }

    @Test fun exitBeforeRegistrationIsNotLost() {
        events.started("one")
        events.exited("one")
        events.observe("one", seen::add)
        drain()
        assertEquals(AgentRuntimeInstanceEvent.Kind.EXITED, seen.single().kind)
        assertEquals(seen.single(), events.interruption("one"))
    }

    @Test fun replacementBeforeRegistrationRemainsObservable() {
        events.started("one")
        events.started("two")
        events.observe("one", seen::add)
        drain()
        assertEquals(AgentRuntimeInstanceEvent.Kind.REPLACED, seen.single().kind)
        assertNull(events.interruption("two"))
    }

    @Test fun lateOldExitCannotRetireNewRuntime() {
        events.started("one")
        events.observe("one", seen::add)
        events.started("two")
        events.observe("two", seen::add)
        events.exited("one")
        drain()
        assertEquals(listOf(AgentRuntimeInstanceEvent("one", AgentRuntimeInstanceEvent.Kind.REPLACED)), seen)
        assertNull(events.interruption("two"))
        events.exited("two")
        drain()
        assertEquals("two", seen.last().instanceId)
        assertEquals(AgentRuntimeInstanceEvent.Kind.EXITED, seen.last().kind)
    }

    @Test fun cancelledListenerDoesNotConsumeAnAlreadyQueuedExit() {
        events.started("one")
        val subscription = events.observe("one", seen::add)
        events.exited("one")
        subscription.close()
        drain()
        assertTrue(seen.isEmpty())
        events.observe("one", seen::add)
        drain()
        assertEquals(1, seen.size)
    }

    @Test fun eachWaitingTaskReceivesOnlyOneEvent() {
        events.started("one")
        var first = 0
        var second = 0
        events.observe("one") { first++ }
        events.observe("one") { second++ }
        events.started("two")
        events.exited("one")
        drain()
        assertEquals(1, first)
        assertEquals(1, second)
    }

    @Test fun unknownHostStateDoesNotInventAnExitAndRetiredIdentityCannotBeReused() {
        assertNull(events.interruption("one"))
        events.started("one")
        events.started("one")
        events.exited("one")
        assertThrows(IllegalStateException::class.java) { events.started("one") }
    }

    @Test fun changedGuestBridgeCannotOpenAChannelToTheReplacement() {
        var opens = 0
        val bridge = AgentRuntimeGuestBridge(AgentRuntimeGuestChannelFactory { opens++; error("No replacement channel") },
            { ByteArray(32) { 1 } }, runtimeInstanceId = "original", runtimeInstanceIsCurrent = { false })
        try {
            assertThrows(IllegalStateException::class.java) { bridge.execute(AgentRuntimeExecutionRequest(
                AgentRuntimeLanguage.SHELL, "true", emptyList(), 1000, false, emptyList(), "public-fixture")) }
            assertEquals(0, opens)
        } finally { bridge.close() }
    }

    @Test fun interruptedMonitorDoesNotInventProcessExit() {
        var callbacks = 0
        val child = object : Process() {
            override fun waitFor(): Int = throw InterruptedException("Public fixture")
            override fun exitValue(): Int = throw IllegalThreadStateException()
            override fun destroy() = Unit
            override fun getInputStream() = java.io.ByteArrayInputStream(byteArrayOf())
            override fun getErrorStream() = java.io.ByteArrayInputStream(byteArrayOf())
            override fun getOutputStream() = java.io.ByteArrayOutputStream()
        }
        val monitor = AgentRuntimeProcessMonitor.start(child) { callbacks++ }
        monitor.join(2000)
        assertFalse(monitor.isAlive)
        assertTrue(monitor.isInterrupted)
        assertEquals(0, callbacks)
    }
}
