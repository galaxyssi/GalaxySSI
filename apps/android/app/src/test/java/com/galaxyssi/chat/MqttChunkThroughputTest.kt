package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttChunkThroughputTest {
    @Test fun coldPathPipelinesPrivacyBucketsWithoutUnboundedGrowth() {
        val stats = MqttChunkThroughput()
        repeat(2) { index ->
            assertTrue(stats.canSend("peer", "emqx", 87419))
            stats.track("peer", MqttChunkThroughput.Chunk("t", "r", index, true), "emqx", 1, 87419, 0)
        }
        assertFalse(stats.canSend("peer", "emqx", 87419))
        stats.confirmed("peer", "t", "r", listOf(0), mapOf("emqx" to 1), 15000)
        // A slow but valid round trip must not collapse the window to one bucket.
        assertTrue(stats.canSend("peer", "emqx", 2 * 87419))
        assertFalse(stats.canSend("peer", "emqx", 524288))
    }

    @Test fun timeoutBacksOffAndResetRestoresColdWindow() {
        val stats = MqttChunkThroughput()
        stats.track("peer", MqttChunkThroughput.Chunk("old", "r", 0, true), "emqx", 1, 87419, 0)
        stats.expire(30001)
        stats.track("peer", MqttChunkThroughput.Chunk("new", "r", 0, true), "emqx", 1, 87419, 30002)
        assertFalse(stats.canSend("peer", "emqx", 87419))
        stats.forget("peer")
        stats.track("peer", MqttChunkThroughput.Chunk("next", "r", 0, true), "emqx", 1, 87419, 30003)
        assertTrue(stats.canSend("peer", "emqx", 87419))
        stats.reset()
        assertEquals(0L, stats.pendingBytes("emqx"))
    }

    @Test fun unknownAndSlowPathsAllowOnlyOneLargePacketUntilPeerConfirmation() {
        val stats = MqttChunkThroughput()
        val chunk = MqttChunkThroughput.Chunk("t", "r", 0, true)
        assertTrue(stats.canSend("peer", "emqx", 699088))
        stats.track("peer", chunk, "emqx", 1, 699088, 0)
        assertFalse(stats.canSend("peer", "emqx", 87419))
        assertTrue(stats.canSend("peer", "hivemq", 87419))
        stats.confirmed("peer", "t", "r", listOf(0), mapOf("emqx" to 1), 10000)
        assertTrue(stats.canSend("peer", "emqx", 87419))
    }

    @Test fun verifiedFastPathsGrowTheirWindowButKeepABoundedBacklog() {
        val stats = MqttChunkThroughput()
        repeat(3) { index ->
            stats.track("peer", MqttChunkThroughput.Chunk("$index", "r", 0, true), "emqx", 1, 87419, index * 1000L)
            stats.confirmed("peer", "$index", "r", listOf(0), mapOf("emqx" to 1), index * 1000L + 100)
        }
        stats.track("peer", MqttChunkThroughput.Chunk("next", "r", 0, true), "emqx", 1, 87419, 3000)
        assertTrue(stats.canSend("peer", "emqx", 87419))
        assertFalse(stats.canSend("peer", "emqx", 524288))
    }
}
