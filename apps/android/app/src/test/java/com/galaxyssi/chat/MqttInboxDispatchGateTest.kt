package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MqttInboxDispatchGateTest {
    @Test fun duplicatesWaitUntilExplicitConsumerCompletion() {
        val gate = MqttInboxDispatchGate()
        assertTrue(gate.acquire("pair-a:message"))
        repeat(20) { assertFalse(gate.acquire("pair-a:message")) }
        gate.release("pair-a:message")
        assertTrue(gate.acquire("pair-a:message"))
    }

    @Test fun differentPairsWithSameBusinessIdDoNotBlockEachOther() {
        val gate = MqttInboxDispatchGate()
        assertTrue(gate.acquire("pair-a:message"))
        assertTrue(gate.acquire("pair-b:message"))
    }

    @Test fun globalWorkIsBoundedWithoutEvictingActiveConsumers() {
        val gate = MqttInboxDispatchGate(2)
        assertTrue(gate.acquire("one")); assertTrue(gate.acquire("two"))
        assertFalse(gate.acquire("three")); assertFalse(gate.acquire("one"))
        gate.release("two")
        assertTrue(gate.acquire("three")); assertFalse(gate.acquire("one"))
    }

    @Test fun concurrentCopiesHaveOneWinner() {
        val gate = MqttInboxDispatchGate()
        val executor = Executors.newFixedThreadPool(10)
        try {
            val results = (1..100).map { executor.submit<Boolean> { gate.acquire("pair:message") } }
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) })
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun invalidKeysAndCapacityAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { MqttInboxDispatchGate(0) }
        assertFalse(MqttInboxDispatchGate().acquire(" "))
    }

    @Test fun resetOnlyResetsDispatchNotDurableReceiptIdentity() {
        val gate = MqttInboxDispatchGate()
        assertTrue(gate.acquire("key")); gate.clear(); assertTrue(gate.acquire("key"))
    }
}
