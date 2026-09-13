package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.MqttException
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

class MqttDeliveryDispatchTest {
    private val hedge = MqttBrokerCatalog.UNMEASURED_HEDGE_MS
    private fun ready() = MqttPoolTestRig().apply {
        start()
        transport.policy.acceptVerifiedResume("peer", MqttMultipathPolicy.PeerRoute(1, MqttBrokerCatalog.brokers.keys,
            MqttBrokerCatalog.PACKET_BYTES, true, 300_000), clock.get())
    }
    private fun descriptor(id: String = "message", traffic: String = "message", size: Int = 2048,
                           authorized: (String, Long) -> Boolean = { _, _ -> true }) =
        MqttDeliveryDispatch.Delivery("peer", MqttDeliveryEnvelope.Message(id, "a".repeat(64), "b".repeat(64), "c".repeat(64), traffic),
            setOf("inbox"), { it.metadata().toString().toByteArray() }, authorized, size)
    private fun packets(rig: MqttPoolTestRig) = rig.clients.values.flatMap { it.last().sent }
    private fun frame(packet: MqttPoolTestRig.Sent): MqttDeliveryEnvelope.Frame =
        MqttDeliveryEnvelope.parseVerifiedReceipt(JSONObject(packet.message.payload.toString(Charsets.UTF_8))
            .put("type", "link_rx_stored").put("status", "RX_STORED"), "b".repeat(64), "c".repeat(64))
    private fun send(rig: MqttPoolTestRig, delivery: MqttDeliveryDispatch.Delivery = descriptor()) =
        rig.transport.publishDelivery("outbox", delivery)
    private fun tick(rig: MqttPoolTestRig, elapsed: Long) {
        rig.clock.addAndGet(elapsed)
        rig.transport.delivery.tick()
    }

    @Test fun pubackFinishesLogicalTokenButDoesNotStopPeerRetry() = ready().use { rig ->
        val token = send(rig)
        assertTrue(token.isComplete)
        assertEquals(1, packets(rig).size)
        tick(rig, hedge - 1)
        assertEquals(1, packets(rig).size)
        tick(rig, 1)
        rig.await { packets(rig).size == 2 }
        tick(rig, hedge)
        rig.await { packets(rig).size == 3 }
        assertEquals(3, packets(rig).map { frame(it).attempt.attemptId }.toSet().size)
        assertEquals(1, rig.completed.count { it.first == token.messageId })
        assertTrue(rig.transport.policy.pending("peer", "message"))
    }

    @Test fun verifiedStorageCancelsOnlyUnsentCopies() = ready().use { rig ->
        send(rig)
        val commits = AtomicInteger()
        assertTrue(rig.transport.delivery.acceptVerifiedReceipt("peer", frame(packets(rig).single())) { commits.incrementAndGet() })
        tick(rig, hedge * 2 + 100)
        assertEquals(1, packets(rig).size)
        assertEquals(1, commits.get())
        assertEquals(0, rig.transport.delivery.diagnostics().messages)
    }

    @Test fun criticalCopiesKeepEachPhysicalSlotUntilPuback() = ready().use { rig ->
        rig.earlyAck = false
        val token = send(rig, descriptor(traffic = "control"))
        assertEquals(3, packets(rig).size)
        assertFalse(token.isComplete)
        assertTrue(rig.transport.delivery.acceptVerifiedReceipt("peer", frame(packets(rig).first())) {})
        assertEquals(3, rig.transport.policy.diagnostics().inflightPackets)
        packets(rig).forEach { it.listener.onSuccess(it.token) }
        tick(rig, 0)
        assertEquals(0, rig.transport.policy.diagnostics().inflightPackets)
        assertEquals(listOf(token.messageId to true), rig.completed.toList())
    }

    @Test fun wrongAttemptPairHashPathAndGenerationCannotCommit() = ready().use { rig ->
        send(rig)
        val original = frame(packets(rig).single())
        val variants = listOf(
            original.copy(attempt = original.attempt.copy(attemptId = "f".repeat(32))),
            original.copy(attempt = original.attempt.copy(generation = 2)),
            original.copy(attempt = original.attempt.copy(brokerId = (MqttBrokerCatalog.brokers.keys - original.attempt.brokerId).first())),
            original.copy(message = original.message.copy(messageId = "other")),
            original.copy(message = original.message.copy(contentHash = "d".repeat(64))),
            original.copy(message = original.message.copy(receiver = "d".repeat(64))))
        variants.forEach { assertFalse(rig.transport.delivery.acceptVerifiedReceipt("peer", it) { fail("Invalid receipt committed") }) }
        assertFalse(rig.transport.delivery.acceptVerifiedReceipt("other", original) { fail("Wrong peer committed") })
        tick(rig, hedge * 2 + 100)
        rig.await { packets(rig).size == 3 }
    }

    @Test fun failedDurableCommitDoesNotStopHedge() = ready().use { rig ->
        send(rig)
        assertThrows(IOException::class.java) {
            rig.transport.delivery.acceptVerifiedReceipt("peer", frame(packets(rig).single())) { throw IOException("disk") }
        }
        tick(rig, hedge)
        rig.await { packets(rig).size == 2 }
    }

    @Test fun duplicateReceiptDoesNotRepeatCommit() = ready().use { rig ->
        send(rig)
        val receipt = frame(packets(rig).single())
        val commits = AtomicInteger()
        assertTrue(rig.transport.delivery.acceptVerifiedReceipt("peer", receipt) { commits.incrementAndGet() })
        assertFalse(rig.transport.delivery.acceptVerifiedReceipt("peer", receipt) { commits.incrementAndGet() })
        assertEquals(1, commits.get())
    }

    @Test fun storedMessageAckCancelsWithoutMakingUpAnRtt() = ready().use { rig ->
        send(rig)
        rig.transport.delivery.acceptVerifiedMessage("peer", "message", "a".repeat(64))
        tick(rig, hedge * 2 + 100)
        assertEquals(1, packets(rig).size)
        assertEquals(hedge, rig.transport.policy.plan("peer", "next", MqttMultipathPolicy.Traffic.MESSAGE,
            1024, setOf("inbox"), rig.clock.get())[1].delayMs)
    }

    @Test fun wrongStoredHashDoesNotCancel() = ready().use { rig ->
        send(rig)
        rig.transport.delivery.acceptVerifiedMessage("peer", "message", "d".repeat(64))
        tick(rig, hedge * 2 + 100)
        rig.await { packets(rig).size == 3 }
    }

    @Test fun everyHedgeRevalidatesAuthorization() = ready().use { rig ->
        var authorized = true
        send(rig, descriptor(authorized = { _, _ -> authorized }))
        authorized = false
        tick(rig, hedge * 2 + 100)
        assertEquals(1, packets(rig).size)
    }

    @Test fun forgottenPeerCannotReceiveDelayedCopies() = ready().use { rig ->
        send(rig)
        rig.transport.policy.forgetPeer("peer")
        tick(rig, hedge * 2 + 100)
        assertEquals(1, packets(rig).size)
    }

    @Test fun revokedSubscriptionsCannotSendDelayedCopies() = ready().use { rig ->
        send(rig)
        rig.transport.policy.unsubscribe(setOf("inbox"))
        tick(rig, hedge * 2 + 100)
        assertEquals(1, packets(rig).size)
    }

    @Test fun progressAndLargePacketsRemainSinglePath() = ready().use { rig ->
        send(rig, descriptor("progress", "progress"))
        send(rig, descriptor("large", size = MqttBrokerCatalog.SMALL_PACKET_BYTES + 1))
        tick(rig, hedge * 2 + 100)
        assertEquals(2, packets(rig).size)
    }

    @Test fun outboxDuplicateReusesOneLiveRoundAndExpiryAllowsNewRound() = ready().use { rig ->
        val first = send(rig)
        assertSame(first, send(rig))
        assertEquals(1, packets(rig).size)
        tick(rig, 31_000)
        assertNotSame(first, send(rig))
        assertEquals(2, packets(rig).size)
        assertEquals(1, rig.transport.delivery.diagnostics().messages)
    }

    @Test fun capacityIsSharedAndReservesTwoControlSlots() = ready().use { rig ->
        rig.earlyAck = false
        repeat(10) { send(rig, descriptor("message-$it")) }
        assertThrows(MqttException::class.java) { send(rig, descriptor("overflow")) }
        send(rig, descriptor("stop", "control"))
        assertEquals(12, rig.transport.policy.diagnostics().inflightPackets)
        tick(rig, hedge * 2 + 100)
        assertEquals(12, packets(rig).size)
        packets(rig).forEach { it.listener.onSuccess(it.token) }
        tick(rig, 300)
        assertTrue(rig.transport.policy.diagnostics().inflightPackets <= 12)
        assertEquals(3, packets(rig).count { frame(it).message.messageId == "stop" })
    }

    @Test fun failedPhysicalPathExpeditesBackups() = ready().use { rig ->
        rig.earlyAck = false
        val token = send(rig)
        val first = packets(rig).single()
        first.listener.onFailure(first.token, IllegalStateException("offline"))
        tick(rig, 10)
        rig.await { packets(rig).size == 3 }
        packets(rig).first { it !== first }.let { it.listener.onSuccess(it.token) }
        assertTrue(token.isComplete)
    }

    @Test fun wrongPubackGenerationDoesNotFreeSlot() = ready().use { rig ->
        rig.earlyAck = false
        send(rig)
        val frame = frame(packets(rig).single())
        rig.transport.delivery.published(MqttBrokerPool.PublishReceipt(1,
            MqttMultipathPolicy.PhysicalKey(frame.attempt.brokerId, 99, 1), frame.attempt.attemptId, true))
        assertEquals(1, rig.transport.policy.diagnostics().inflightPackets)
        assertTrue(rig.completed.isEmpty())
    }

    @Test fun encodedOverheadCannotExceedBound() = ready().use { rig ->
        assertThrows(IllegalArgumentException::class.java) { send(rig, descriptor(size = 50)) }
        assertTrue(packets(rig).isEmpty())
        assertEquals(0, rig.transport.delivery.diagnostics().messages)
    }

    @Test fun closeCancelsOnlyThisOwnerAndCompletesTokenOnce() = ready().use { rig ->
        rig.earlyAck = false
        val token = send(rig)
        rig.transport.close()
        tick(rig, 2000)
        assertFalse(token.isComplete)
        assertEquals(1, packets(rig).size)
        assertEquals(1, rig.completed.count { it.first == token.messageId })
        assertEquals(0, rig.transport.delivery.diagnostics().messages)
        assertEquals(0, rig.transport.delivery.diagnostics().trackedAttempts)
    }
}
