package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttChunkFlowTest {
    @Test fun sparseSamplesKeepBootstrapAndBatchBytesCountOnlyOnce() {
        val flow = MqttChunkThroughput()
        repeat(3) { number ->
            val chunk = MqttChunkThroughput.Chunk("transfer-$number", "request", 0, true)
            val start = number * 3000L
            flow.track("peer", chunk, "hivemq", 1, 524288, start)
            flow.track("peer", chunk.copy(index = 1), "hivemq", 1, 524288, start)
            flow.confirmed("peer", chunk.transfer, "request", listOf(0, 1), mapOf("hivemq" to 1L), start + 500)
            assertEquals(if (number < 2) 262144.0 else 2097152.0, flow.rate("peer", "hivemq"), 0.001)
            flow.confirmed("peer", chunk.transfer, "request", listOf(0, 1), mapOf("hivemq" to 1L), start + 600)
            assertEquals(if (number < 2) 262144.0 else 2097152.0, flow.rate("peer", "hivemq"), 0.001)
        }
        assertEquals(0L, flow.pendingBytes("hivemq"))
    }
    @Test fun RetriesAndAmbiguousCopiesCannotCreateSpeedSamples() {
        for (retry in listOf(true, false)) {
            val flow = MqttChunkThroughput()
            repeat(3) { index ->
                val chunk = MqttChunkThroughput.Chunk("transfer-$index", "request", 0, !retry)
                flow.track("peer", chunk, "emqx", 1, 524288, 1000)
                if (!retry) flow.track("peer", chunk, "hivemq", 1, 524288, 1100)
                flow.confirmed("peer", chunk.transfer, "request", listOf(0), mapOf("emqx" to 1L, "hivemq" to 1L), 1200)
            }
            assertEquals(262144.0, flow.rate("peer", "emqx"), 0.001)
            assertEquals(0L, flow.pendingBytes("emqx"))
        }
    }
    @Test fun wrongPairRequestAndGenerationCannotCreditPath() {
        val flow = MqttChunkThroughput()
        val chunk = MqttChunkThroughput.Chunk("transfer", "request", 0, true)
        flow.track("peer", chunk, "emqx", 1, 100, 1000)
        flow.confirmed("other", "transfer", "request", listOf(0), mapOf("emqx" to 1L), 2000)
        flow.confirmed("peer", "transfer", "old", listOf(0), mapOf("emqx" to 1L), 2000)
        assertEquals(100L, flow.pendingBytes("emqx"))
        flow.confirmed("peer", "transfer", "request", listOf(0), mapOf("emqx" to 2L), 2000)
        assertEquals(0L, flow.pendingBytes("emqx"))
        assertEquals(262144.0, flow.rate("peer", "emqx"), 0.001)
    }
    @Test fun newRoundAndExpiryRetireOnlyObservations() {
        val flow = MqttChunkThroughput()
        flow.track("peer", MqttChunkThroughput.Chunk("transfer", "old", 0, true), "emqx", 1, 100, 1000)
        flow.track("peer", MqttChunkThroughput.Chunk("transfer", "new", 1, false), "hivemq", 1, 200, 2000)
        assertEquals(0L, flow.pendingBytes("emqx"))
        assertEquals(200L, flow.pendingBytes("hivemq"))
        flow.expire(33000)
        assertEquals(0L, flow.pendingBytes("hivemq"))
    }
    private fun policy() = MqttMultipathPolicy(byteArrayOf(1)).apply {
        MqttBrokerCatalog.brokers.keys.forEach { connected(it, 1); subscribed(it, 1, setOf("inbox")) }
        acceptVerifiedResume("peer", MqttMultipathPolicy.PeerRoute(1, MqttBrokerCatalog.brokers.keys, 1048576, true, 300000), 0)
    }
    @Test fun measuredFastPathWinsAndNetworkChangesClearItsAdvantage() {
        val policy = policy()
        repeat(3) { number ->
            val paths = listOf("hivemq" to 250L, "mosquitto" to 1000L, "emqx" to 2000L)
            val start = number * 4000L
            for ((broker, _) in paths) {
                val chunk = MqttChunkThroughput.Chunk("$broker-$number", "request", 0, true)
                policy.trackChunk("peer", chunk, broker, 1, 524288, start)
            }
            for ((broker, elapsed) in paths) {
                val chunk = MqttChunkThroughput.Chunk("$broker-$number", "request", 0, true)
                policy.confirmChunkState("peer", chunk.transfer, "request", listOf(0), start + elapsed)
            }
        }
        assertEquals("hivemq", policy.plan("peer", "next", MqttMultipathPolicy.Traffic.CHUNK, 524288, setOf("inbox"), 12000).first().brokerId)
        policy.setNetwork("new-wifi")
        assertEquals(policy().plan("peer", "next", MqttMultipathPolicy.Traffic.CHUNK, 524288, setOf("inbox"), 12000),
            policy.plan("peer", "next", MqttMultipathPolicy.Traffic.CHUNK, 524288, setOf("inbox"), 12000))
    }
    @Test fun brokerOnlyAckDoesNotMakeAPathLookEmpty() {
        val policy = policy()
        val first = policy.plan("peer", "first", MqttMultipathPolicy.Traffic.CHUNK, 524288, setOf("inbox"), 1000).first().brokerId
        policy.trackChunk("peer", MqttChunkThroughput.Chunk("transfer", "request", 0, true), first, 1, 524288, 1000)
        val next = policy.plan("peer", "second", MqttMultipathPolicy.Traffic.CHUNK, 524288, setOf("inbox"), 1000).first().brokerId
        assertNotEquals(first, next)
        assertEquals(0, policy.diagnostics().inflightPackets)
    }
    @Test fun expiryAndRevocationKeepPairsSeparate() {
        val flow = MqttChunkThroughput()
        repeat(3) { index ->
            for (peer in listOf("a", "b"))
                flow.track(peer, MqttChunkThroughput.Chunk("transfer-$index", "request", 0, true), "emqx", 1, 100, index * 2000L)
            for (peer in listOf("a", "b"))
                flow.confirmed(peer, "transfer-$index", "request", listOf(0), mapOf("emqx" to 1L), index * 2000L + 1000)
        }
        flow.forget("a")
        assertEquals(262144.0, flow.rate("a", "emqx"), 0.001)
        assertEquals(100.0, flow.rate("b", "emqx"), 0.001)
        flow.expire(306000)
        assertEquals(262144.0, flow.rate("b", "emqx"), 0.001)
    }
    @Test fun observationMemoryRemainsBoundedWithoutPeerAck() {
        val flow = MqttChunkThroughput()
        repeat(MqttBrokerCatalog.MAX_ATTEMPTS + 3) {
            flow.track("peer", MqttChunkThroughput.Chunk("$it", "request", 0, true), "emqx", 1, 100, 0)
        }
        assertEquals(MqttBrokerCatalog.MAX_ATTEMPTS * 100L, flow.pendingBytes("emqx"))
        flow.forget("peer")
        assertEquals(0L, flow.pendingBytes("emqx"))
    }
    @Test fun burstKeepsLatestRevisionAndOriginalDeadline() {
        val feedback = MqttChunkFeedback()
        val sent = mutableListOf<Int>()
        feedback.offer("peer", "transfer", "request", 1, { sent.add(1) }, 0)
        feedback.offer("peer", "transfer", "request", 3, { sent.add(3) }, 150)
        feedback.offer("peer", "transfer", "request", 2, { sent.add(2) }, 160)
        assertTrue(feedback.drain(199).isEmpty())
        feedback.drain(201).forEach { it() }
        assertEquals(listOf(3), sent)
    }
    @Test fun terminalOrProbeSendsImmediatelyAndDropsQueuedPartial() {
        val feedback = MqttChunkFeedback()
        val sent = mutableListOf<Int>()
        feedback.offer("peer", "transfer", "request", 1, { sent.add(1) }, 0)
        feedback.offer("peer", "transfer", "request", 2, { sent.add(2) }, 100, urgent = true)!!.invoke()
        assertEquals(listOf(2), sent)
        assertTrue(feedback.drain(1000).isEmpty())
    }
    @Test fun feedbackPeerQuotaKeepsRoomForOtherPairs() {
        val feedback = MqttChunkFeedback()
        val sent = mutableListOf<String>()
        repeat(MqttBrokerCatalog.PEER_CHUNK_FEEDBACK + 1) { feedback.offer("peer", "$it", "request", 1, { sent.add("peer") }, 0) }
        feedback.offer("other", "transfer", "request", 1, { sent.add("other") }, 0)
        feedback.forget("peer")
        feedback.drain(1000).forEach { it() }
        assertEquals(listOf("other"), sent)
    }
    @Test fun feedbackDrainIsBounded() {
        val feedback = MqttChunkFeedback()
        repeat(30) { feedback.offer("peer", "$it", "request", 1, {}, 0) }
        assertEquals(16, feedback.drain(1000).size)
        assertEquals(14, feedback.drain(1000).size)
    }
}
