package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MqttHedgePolicyDeviceTest {
    private val brokers = MqttBrokerCatalog.brokers.keys
    private val hash = "a".repeat(64)

    private fun policy() = MqttMultipathPolicy().apply {
        brokers.forEach { connected(it, 1); subscribed(it, 1, setOf("inbox")) }
        acceptVerifiedResume("peer", MqttMultipathPolicy.PeerRoute(1, brokers, MqttBrokerCatalog.PACKET_BYTES,
            true, 300_000), 0)
    }

    private fun attempt(broker: String, message: String = "message",
                        traffic: MqttMultipathPolicy.Traffic = MqttMultipathPolicy.Traffic.MESSAGE) =
        MqttMultipathPolicy.Attempt("peer", message, hash, broker, 1, 1024, traffic, 0)

    @Test fun sparseSamplesDoNotChangeColdHedgeDelay() {
        val policy = policy()
        repeat(MqttBrokerCatalog.HEDGE_MIN_SAMPLES) { index ->
            val message = "sample-$index"
            assertTrue(policy.reserve(message, attempt("mosquitto", message)))
            assertTrue(policy.brokerAck(message, "mosquitto", 1))
            assertEquals(setOf(message), policy.acceptVerifiedReceipt("peer", message, hash, message, 20))
            val plan = policy.plan("peer", "next", MqttMultipathPolicy.Traffic.MESSAGE, 1024, setOf("inbox"), 1000)
            assertEquals(if (index + 1 < MqttBrokerCatalog.HEDGE_MIN_SAMPLES) 500L else 100L, plan[1].delayMs)
        }
    }

    @Test fun brokerAcknowledgementDoesNotMeanPeerStored() {
        val policy = policy()
        assertTrue(policy.reserve("attempt", attempt("hivemq")))
        assertTrue(policy.brokerAck("attempt", "hivemq", 1))
        assertTrue(policy.pending("peer", "message"))
        assertEquals(0, policy.diagnostics().inflightPackets)
        assertEquals(setOf("attempt"), policy.acceptVerifiedReceipt("peer", "message", hash, "attempt", 100))
        assertFalse(policy.pending("peer", "message"))
    }

    @Test fun receivedControlCopiesHoldSlotsUntilTheirOwnBrokerAck() {
        val policy = policy()
        brokers.forEach { assertTrue(policy.reserve(it, attempt(it, traffic = MqttMultipathPolicy.Traffic.CONTROL))) }
        assertEquals(brokers, policy.acceptVerifiedReceipt("peer", "message", hash, "emqx", 50))
        assertEquals(3, policy.diagnostics().inflightPackets)
        brokers.forEach { assertTrue(policy.brokerAck(it, it, 1)) }
        assertEquals(0, policy.diagnostics().inflightPackets)
    }

    @Test fun wrongPairOrCiphertextCannotFinishTheRace() {
        val policy = policy()
        policy.reserve("attempt", attempt("emqx"))
        assertTrue(policy.acceptVerifiedReceipt("another", "message", hash, "attempt", 10).isEmpty())
        assertTrue(policy.acceptVerifiedReceipt("peer", "message", "b".repeat(64), "attempt", 10).isEmpty())
        assertTrue(policy.pending("peer", "message"))
    }
}
