package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class MqttMultipathPolicyTest {
    private val brokers = MqttBrokerCatalog.brokers.keys
    private val hash = "a".repeat(64)
    private fun ready(): MqttMultipathPolicy = MqttMultipathPolicy("deterministic-test".toByteArray()).apply {
        brokers.forEach { connected(it, 1); subscribed(it, 1, setOf("inbox")) }
        acceptVerifiedResume("peer", route(), 0)
    }
    private fun route(epoch: Long = 1, paths: Set<String> = brokers, expiry: Long = 300_000,
                      size: Int = MqttBrokerCatalog.PACKET_BYTES, chunkAcks: Boolean = true) =
        MqttMultipathPolicy.PeerRoute(epoch, paths, size, chunkAcks, expiry)
    private fun plan(policy: MqttMultipathPolicy, traffic: MqttMultipathPolicy.Traffic = MqttMultipathPolicy.Traffic.MESSAGE,
                     message: String = "m", peer: String = "peer", size: Int = 100, now: Long = 1000,
                     ingress: String? = null, attempted: Set<String> = emptySet()) =
        policy.plan(peer, message, traffic, size, setOf("inbox"), now, ingress, attempted)
    private fun attempt(path: String = "emqx", peer: String = "peer", message: String = "m",
                        size: Int = 100, traffic: MqttMultipathPolicy.Traffic = MqttMultipathPolicy.Traffic.MESSAGE,
                        contentHash: String = hash) =
        MqttMultipathPolicy.Attempt(peer, message, contentHash, path, 1, size, traffic, 0)

    @Test fun firstSubscribedCommonPathWorksForAllSixStartupOrders() {
        for (first in brokers) for (second in brokers - first) {
            val order = listOf(first, second, (brokers - first - second).single())
            val policy = MqttMultipathPolicy()
            policy.acceptVerifiedResume("peer", route(), 0)
            order.forEachIndexed { index, broker ->
                policy.connected(broker, 1)
                assertEquals(index, plan(policy, MqttMultipathPolicy.Traffic.CONTROL).size)
                policy.subscribed(broker, 1, setOf("inbox"))
                assertEquals(order.take(index + 1).toSet(), plan(policy, MqttMultipathPolicy.Traffic.CONTROL)
                    .map { it.brokerId }.toSet())
            }
        }
    }

    @Test fun noDefaultProviderOrUnverifiedBusinessPath() {
        val policy = ready()
        assertTrue(plan(policy, peer = "unknown").isEmpty())
        assertEquals(brokers, (0 until 100).map { plan(policy, message = it.toString()).first().brokerId }.toSet())
    }

    @Test fun textHedgesButCriticalControlRacesImmediately() {
        val policy = ready()
        assertEquals(listOf(0L, 500L, 1000L), plan(policy).map { it.delayMs })
        assertEquals(listOf(0L, 0L, 0L), plan(policy, MqttMultipathPolicy.Traffic.CONTROL).map { it.delayMs })
    }

    @Test fun progressAndLargePacketsAreNotTripled() {
        val policy = ready()
        assertEquals(1, plan(policy, size = 65_537).size)
        assertEquals(1, plan(policy, MqttMultipathPolicy.Traffic.FINAL, size = 65_537).size)
        assertEquals(1, plan(policy, MqttMultipathPolicy.Traffic.PROGRESS).size)
        assertEquals(1, plan(policy, MqttMultipathPolicy.Traffic.CHUNK).size)
    }

    @Test fun receiptsPreferIngressAndDoNotRace() {
        val policy = ready()
        brokers.forEach { broker -> assertEquals(listOf(broker), plan(policy,
            MqttMultipathPolicy.Traffic.RECEIPT, ingress = broker).map { it.brokerId }) }
    }

    @Test fun oneDisconnectDoesNotInvalidateOtherPaths() {
        val policy = ready()
        policy.disconnected("emqx", 1)
        assertEquals(brokers - "emqx", plan(policy).map { it.brokerId }.toSet())
    }

    @Test fun staleCallbacksCannotChangeNewGeneration() {
        val policy = ready()
        policy.connected("emqx", 2)
        assertFalse(policy.disconnected("emqx", 1))
        assertFalse(policy.subscribed("emqx", 1, setOf("inbox")))
        assertFalse(plan(policy).any { it.brokerId == "emqx" })
        assertTrue(policy.subscribed("emqx", 2, setOf("inbox")))
        assertTrue(plan(policy).any { it.brokerId == "emqx" })
        assertNotEquals(MqttMultipathPolicy.PhysicalKey("emqx", 1, 7),
            MqttMultipathPolicy.PhysicalKey("hivemq", 1, 7))
    }

    @Test fun allOfflineThenAnyOnePathCanRecover() {
        val policy = ready()
        brokers.forEach { policy.disconnected(it, 1) }
        assertTrue(plan(policy).isEmpty())
        policy.connected("mosquitto", 2)
        policy.subscribed("mosquitto", 2, setOf("inbox"))
        assertEquals(listOf("mosquitto"), plan(policy).map { it.brokerId })
    }

    @Test fun peerReceiveSetRestrictsSendingAndNoIntersectionQueues() {
        val policy = ready()
        policy.acceptVerifiedResume("peer", route(2, setOf("hivemq")), 0)
        assertEquals(listOf("hivemq"), plan(policy).map { it.brokerId })
        policy.disconnected("hivemq", 1)
        assertTrue(plan(policy).isEmpty())
    }

    @Test fun resumeReplaysCannotRevertOrExtendRoutes() {
        val policy = ready()
        assertTrue(policy.acceptVerifiedResume("peer", route(2, expiry = 200_000), 0))
        assertFalse(policy.acceptVerifiedResume("peer", route(1), 0))
        assertFalse(policy.acceptVerifiedResume("peer", route(2, expiry = 250_000), 0))
        assertTrue(plan(policy, now = 201_000).isEmpty())
    }

    @Test fun invalidCapabilitiesAndMissingChunkReceiptsAreRejected() {
        val policy = ready()
        for (route in listOf(route(0), route(2, setOf("unknown")), route(2, size = 0),
                             route(2, expiry = 300_001), route(2, size = 1_048_577))) {
            assertFalse(policy.acceptVerifiedResume("peer", route, 0))
        }
        policy.acceptVerifiedResume("peer", route(2, chunkAcks = false), 0)
        assertTrue(plan(policy, MqttMultipathPolicy.Traffic.CHUNK).isEmpty())
    }

    @Test fun pathAndPeerPacketLimitsUseEncodedSize() {
        val policy = ready()
        policy.acceptVerifiedResume("peer", route(2, size = 1024), 0)
        assertTrue(plan(policy, size = 1025).isEmpty())
        policy.connected("emqx", 2, 512)
        policy.subscribed("emqx", 2, setOf("inbox"))
        assertFalse(plan(policy, size = 1024).any { it.brokerId == "emqx" })
    }

    @Test fun brokerAckDoesNotEndMessageRace() {
        val policy = ready()
        assertTrue(policy.reserve("attempt", attempt()))
        assertFalse(policy.brokerAck("attempt", "hivemq", 1))
        assertTrue(policy.brokerAck("attempt", "emqx", 1))
        assertTrue(policy.pending("peer", "m"))
        assertEquals(0, policy.diagnostics().inflightPackets)
    }

    @Test fun verifiedReceiptIsBoundAndRetiresMatchingCopiesOnly() {
        val policy = ready()
        brokers.forEach { policy.reserve(it, attempt(path = it)) }
        policy.reserve("another", attempt(message = "another"))
        assertTrue(policy.acceptVerifiedReceipt("other", "m", hash, "emqx", 200).isEmpty())
        assertTrue(policy.acceptVerifiedReceipt("peer", "m", "b".repeat(64), "emqx", 200).isEmpty())
        assertEquals(brokers, policy.acceptVerifiedReceipt("peer", "m", hash, "emqx", 200))
        assertTrue(policy.pending("peer", "another"))
    }

    @Test fun changedHashCannotReuseMessageId() {
        val policy = ready()
        assertTrue(policy.reserve("one", attempt()))
        assertFalse(policy.reserve("two", attempt(contentHash = "b".repeat(64))))
    }

    @Test fun measuredRttChangesRankingButNewNetworkClearsIt() {
        val policy = ready()
        policy.setNetwork("wifi")
        policy.reserve("fast", attempt(path = "mosquitto"))
        policy.acceptVerifiedReceipt("peer", "m", hash, "fast", 20)
        assertEquals("mosquitto", plan(policy).first().brokerId)
        assertEquals(100L, plan(policy)[1].delayMs)
        policy.setNetwork("cellular")
        assertEquals(500L, plan(policy)[1].delayMs)
    }

    @Test fun chunkRetriesAvoidPreviousPath() {
        val policy = ready()
        val first = plan(policy, MqttMultipathPolicy.Traffic.CHUNK).first().brokerId
        assertNotEquals(first, plan(policy, MqttMultipathPolicy.Traffic.CHUNK, attempted = setOf(first)).first().brokerId)
    }

    @Test fun capacityIsGlobalAndReservesControlSlots() {
        val policy = ready()
        repeat(10) { assertTrue(policy.reserve("$it", attempt(peer = "$it", traffic = MqttMultipathPolicy.Traffic.CHUNK))) }
        assertFalse(policy.reserve("ordinary", attempt()))
        assertTrue(policy.reserve("stop", attempt(traffic = MqttMultipathPolicy.Traffic.CONTROL)))
        assertTrue(policy.reserve("final", attempt(traffic = MqttMultipathPolicy.Traffic.FINAL)))
        assertFalse(policy.reserve("extra", attempt(traffic = MqttMultipathPolicy.Traffic.CONTROL)))
        assertEquals(12, policy.diagnostics().inflightPackets)
    }

    @Test fun concurrentReservationsCannotExceedLimits() {
        val policy = ready()
        val executor = Executors.newFixedThreadPool(20)
        try {
            val results = executor.invokeAll((0 until 200).map { index -> Callable {
                policy.reserve("$index", attempt(peer = "$index", traffic = MqttMultipathPolicy.Traffic.CHUNK))
            } })
            assertEquals(10, results.count { it.get() })
        } finally { executor.shutdownNow() }
    }

    @Test fun perPeerBytesAndExpiredAttemptsAreBounded() {
        val policy = ready()
        assertTrue(policy.reserve("one", attempt(size = 1_048_576)))
        assertTrue(policy.reserve("two", attempt(size = 917_504)))
        assertFalse(policy.reserve("three", attempt()))
        assertEquals(setOf("one", "two"), policy.expireAttempts(1))
        assertEquals(0L, policy.diagnostics().inflightBytes)
    }

    @Test fun fastestPeerReceiptDoesNotReleaseInFlightCopies() {
        val policy = ready()
        brokers.forEach { policy.reserve(it, attempt(path = it)) }
        policy.acceptVerifiedReceipt("peer", "m", hash, "hivemq", 200)
        assertFalse(policy.pending("peer", "m"))
        assertEquals(3, policy.diagnostics().inflightPackets)
        policy.brokerAck("hivemq", "hivemq", 1)
        assertEquals(2, policy.diagnostics().inflightPackets)
        policy.disconnected("emqx", 1)
        policy.brokerAck("mosquitto", "mosquitto", 1)
        assertEquals(0, policy.diagnostics().pendingAttempts)
    }

    @Test fun inflightLoadDistributesChunksAcrossEqualPaths() {
        val policy = ready()
        val selected = mutableSetOf<String>()
        repeat(3) { index ->
            val path = plan(policy, MqttMultipathPolicy.Traffic.CHUNK, size = 1_048_576).first().brokerId
            selected.add(path)
            assertTrue(policy.reserve("$index", attempt(path = path, peer = "$index", size = 1_048_576)))
        }
        assertEquals(brokers, selected)
    }

    @Test fun revocationRemovesPeerRouteAndPendingCopies() {
        val policy = ready()
        policy.reserve("attempt", attempt())
        policy.forgetPeer("peer")
        assertTrue(plan(policy).isEmpty())
        assertFalse(policy.pending("peer", "m"))
    }

    @Test fun unsubscribeInvalidatesAllPaths() {
        val policy = ready()
        policy.unsubscribe(setOf("inbox"))
        assertTrue(plan(policy).isEmpty())
    }
}
