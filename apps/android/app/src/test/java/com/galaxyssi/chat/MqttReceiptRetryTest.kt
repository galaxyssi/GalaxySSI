package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttReceiptRetryTest {
    private val queue = MqttReceiptRetry()
    private val delay = MqttBrokerCatalog.RECEIPT_RETRY_MS
    private fun tick(now: Long, limit: Int = 16) { queue.drain(now, limit).forEach { it() } }

    @Test fun successfulReceiptIsNotRetried() {
        var calls = 0
        queue.offer("p", "m", "a", { calls++; true }, 0)
        tick(20_000)
        assertEquals(1, calls)
    }

    @Test fun unreadyAndExceptionRetainBoundedRetry() {
        var calls = 0
        queue.offer("p", "m", "a", { calls++; if (calls == 2) error("full"); calls == 3 }, 0)
        tick(delay / 2)
        assertEquals(1, calls)
        assertThrows(IllegalStateException::class.java) { tick(delay) }
        tick(delay * 2)
        tick(delay * 3)
        assertEquals(3, calls)
    }

    @Test fun duplicateDoesNotReplaceProofOrExtendExpiry() {
        var calls = 0
        queue.offer("p", "m", "a", { calls++; false }, 0)
        queue.offer("p", "m", "a", { error("replacement") }, 1)
        tick(MqttBrokerCatalog.RECEIPT_RETRY_TTL_MS)
        assertEquals(1, calls)
    }

    @Test fun revokedScopeCannotRunPreviouslyDrainedWork() {
        var calls = 0
        queue.offer("p", "m", "a", { calls++; false }, 0)
        val work = queue.drain(delay)
        queue.forget("p")
        work.forEach { it() }
        assertEquals(1, calls)
    }

    @Test fun perPeerAndGlobalBudgetsAreBounded() {
        var calls = 0
        repeat(MqttBrokerCatalog.MAX_PENDING_RECEIPTS) { index ->
            queue.offer((index / MqttBrokerCatalog.PEER_PENDING_RECEIPTS).toString(), index.toString(), "a", { calls++; false }, 0)
        }
        queue.offer("0", "overflow", "a", { error("peer overflow") }, 0)
        queue.offer("new", "overflow", "a", { error("global overflow") }, 0)
        assertEquals(MqttBrokerCatalog.MAX_PENDING_RECEIPTS, calls)
    }

    @Test fun boundedDrainRotatesUnreadyPeers() {
        val calls = mutableListOf<String>()
        listOf("a", "b", "c").forEach { peer -> queue.offer(peer, "m", "a", { calls.add(peer); false }, 0) }
        calls.clear()
        tick(delay, 1)
        tick(delay * 2, 1)
        assertEquals(listOf("a", "b"), calls)
    }

    @Test fun reentrantDrainCannotSendTwice() {
        var calls = 0
        queue.offer("p", "m", "a", { calls++; tick(delay); true }, 0)
        assertEquals(1, calls)
    }
}
