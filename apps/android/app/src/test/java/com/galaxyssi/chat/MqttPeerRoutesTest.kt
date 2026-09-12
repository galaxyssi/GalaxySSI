package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class MqttPeerRoutesTest {
    private val rig = MqttPoolTestRig()
    private val binding = MqttPeerRoutes.Binding("pair", "a".repeat(64), "b".repeat(64), "c".repeat(43),
        "outbox", setOf("outbox"), setOf("inbox"))
    private class Store : MqttPeerRoutes.Persistence {
        val issued = mutableMapOf<String, MqttRouteAdvertisement>()
        val recorded = mutableMapOf<String, MqttRouteAdvertisement>()
        val forgotten = mutableListOf<String>()
        private val counters = mutableMapOf<String, Long>()
        override fun issue(peer: String, sender: String, receiver: String, brokers: Set<String>, at: Long): MqttRouteAdvertisement {
            val epoch = (counters[peer] ?: 0L) + 1
            counters[peer] = epoch
            return MqttRouteAdvertisement(sender, receiver, epoch, UUID.randomUUID().toString().replace("-", ""),
                at, at + MqttBrokerCatalog.RESUME_TTL_MS, brokers, MqttBrokerCatalog.PACKET_BYTES).also { issued[peer] = it }
        }
        override fun record(peer: String, advertisement: MqttRouteAdvertisement, at: Long): Boolean {
            val old = recorded[peer]
            if (old != null && advertisement.epoch <= old.epoch) return advertisement == old
            recorded[peer] = advertisement
            return true
        }
        override fun forget(peer: String) { recorded.remove(peer); forgotten.add(peer) }
    }
    private val store = Store()
    private val notifications = mutableListOf<String>()
    private val routes = MqttPeerRoutes(rig.transport, store, { raw, _ -> raw }, notifications::add,
        now = rig.clock::get, wall = rig.wall::get)
    @After fun close() { rig.close() }
    private fun start(bindings: List<MqttPeerRoutes.Binding> = listOf(binding)) {
        routes.replace(bindings)
        rig.classifier = routes::classify
        rig.start(bindings.flatMapTo(linkedSetOf()) { it.receiveTopics })
        routes.maintenance()
    }
    private fun remote(ours: MqttPeerRoutes.Binding = binding, epoch: Long = 1, brokers: Set<String> = setOf("hivemq")) =
        MqttRouteAdvertisement(ours.receiver, ours.sender, epoch, epoch.toString(16).padStart(32, '0'), rig.wall.get(),
            rig.wall.get() + MqttBrokerCatalog.RESUME_TTL_MS, brokers, MqttBrokerCatalog.PACKET_BYTES)
    private fun ack(ours: MqttPeerRoutes.Binding = binding, advertisement: MqttRouteAdvertisement = remote(ours)): JSONObject {
        val local = store.issued.getValue(ours.scope)
        return JSONObject().put("type", "link_resume_ack").put("advertisement", advertisement.toWire())
            .put("acknowledged_resume_id", local.resumeId).put("acknowledged_route_epoch", local.epoch)
            .put("acknowledged_digest", local.digest())
    }
    private fun receive(payload: JSONObject, ours: MqttPeerRoutes.Binding = binding, broker: String = "hivemq") =
        routes.handleVerified(ours.scope, payload, rig.ingress(broker), ours.identity)
    private fun sentCount() = rig.clients.values.flatten().sumOf { it.sent.size }

    private fun wire() = JSONObject().put("scheme", "signal").put("from", "alice").put("to", "bob")
        .put("signal_type", "prekey").put("message_type", 3).put("body", "AQIDBA==")
    private fun deliveryFrames() = rig.clients.values.flatten().flatMap { it.sent }.mapNotNull {
        val value = JSONObject(String(it.message.payload, Charsets.UTF_8))
        if (!value.has(MqttDeliveryEnvelope.FIELD)) null else MqttDeliveryEnvelope.parseVerifiedFrame(value,
            binding.sender, binding.receiver, value.getJSONObject(MqttDeliveryEnvelope.FIELD).getString("broker_id"))
    }
    private fun publishDelivery(traffic: MqttMultipathPolicy.Traffic = MqttMultipathPolicy.Traffic.MESSAGE) {
        val delivery = requireNotNull(routes.prepareDelivery("outbox", wire(), "message", traffic))
        rig.transport.publishDelivery("outbox", delivery)
    }

    @Test fun preparedDeliveryUsesAuthenticatedRouteAndOwnsImmutableSignalCopy() {
        start()
        assertNull(routes.prepareDelivery("outbox", wire(), "message", MqttMultipathPolicy.Traffic.MESSAGE))
        receive(ack())
        val original = wire()
        val delivery = requireNotNull(routes.prepareDelivery("outbox", original, "message", MqttMultipathPolicy.Traffic.MESSAGE))
        original.put("body", "changed")
        rig.transport.publishDelivery("outbox", delivery)
        val frame = deliveryFrames().single()
        assertEquals("hivemq", frame.attempt.brokerId)
        assertEquals(MqttDeliveryEnvelope.contentHash(wire()), frame.message.contentHash)
        assertEquals(binding.scope, delivery.peer)
        assertEquals(1, rig.completed.size)
        assertEquals(1, rig.transport.delivery.diagnostics().messages)
    }

    @Test fun storedAckOnAnotherBrokerCommitsOnceAndCancelsOnlyUnsentCopies() {
        start()
        receive(ack(advertisement = remote(brokers = MqttBrokerCatalog.brokers.keys)))
        publishDelivery()
        val frame = deliveryFrames().single()
        val receipt = frame.receiptAfterStore("message", frame.message.contentHash)
        val alternate = MqttBrokerCatalog.brokers.keys.first { it != frame.attempt.brokerId }
        var committed = 0
        assertEquals(true to true, routes.acceptDeliveryReceipt(binding.scope, receipt, rig.ingress(alternate), binding.identity) { committed++ })
        assertEquals(true to false, routes.acceptDeliveryReceipt(binding.scope, receipt, rig.ingress(alternate), binding.identity) { committed++ })
        rig.clock.addAndGet(2_000)
        rig.transport.delivery.tick()
        assertEquals(1, committed)
        assertEquals(1, deliveryFrames().size)
        assertEquals(0, rig.transport.delivery.diagnostics().messages)
    }

    @Test fun failedReceiptCommitLeavesBackupEligible() {
        start()
        receive(ack(advertisement = remote(brokers = MqttBrokerCatalog.brokers.keys)))
        publishDelivery()
        val frame = deliveryFrames().single()
        assertThrows(IllegalStateException::class.java) {
            routes.acceptDeliveryReceipt(binding.scope, frame.receiptAfterStore("message", frame.message.contentHash),
                rig.ingress(frame.attempt.brokerId), binding.identity) { error("storage unavailable") }
        }
        rig.clock.addAndGet(1_000)
        rig.transport.delivery.tick()
        assertEquals(3, deliveryFrames().size)
    }

    @Test fun receiptWrongIdentityOrChangedPairCannotCommit() {
        start()
        receive(ack())
        publishDelivery()
        val frame = deliveryFrames().single()
        val receipt = frame.receiptAfterStore("message", frame.message.contentHash)
        var committed = 0
        assertThrows(IllegalArgumentException::class.java) {
            routes.acceptDeliveryReceipt(binding.scope, receipt, rig.ingress("hivemq"), binding.identity.dropLast(1) + "d".repeat(43)) { committed++ }
        }
        routes.replace(listOf(binding.copy(secret = "d".repeat(43))))
        assertThrows(IllegalArgumentException::class.java) {
            routes.acceptDeliveryReceipt(binding.scope, receipt, rig.ingress("hivemq"), binding.identity) { committed++ }
        }
        assertEquals(0, committed)
    }

    @Test fun lateReceiptFromDisconnectedGenerationCannotCommit() {
        start()
        receive(ack())
        publishDelivery()
        val frame = deliveryFrames().single()
        val ingress = rig.ingress("hivemq")
        rig.client("hivemq").lose()
        rig.await { rig.transport.readyPathGenerations(binding.receiveTopics)["hivemq"] == 2L }
        var committed = 0
        assertEquals(true to false, routes.acceptDeliveryReceipt(binding.scope,
            frame.receiptAfterStore("message", frame.message.contentHash), ingress, binding.identity) { committed++ })
        assertEquals(0, committed)
    }

    @Test fun preparedDeliveryCannotOutlivePairRevocation() {
        start()
        receive(ack(advertisement = remote(brokers = MqttBrokerCatalog.brokers.keys)))
        publishDelivery()
        routes.replace(emptyList())
        rig.clock.addAndGet(1_000)
        rig.transport.delivery.tick()
        assertEquals(1, deliveryFrames().size)
    }

    @Test fun storedReceiptRequiresExactProofAndUsesOriginalPathWithoutRequestingAck() {
        start()
        receive(ack(advertisement = remote(brokers = MqttBrokerCatalog.brokers.keys)))
        val message = MqttDeliveryEnvelope.Message("inbound", MqttDeliveryEnvelope.contentHash(wire()),
            binding.receiver, binding.sender, "message")
        val frame = MqttDeliveryEnvelope.Frame(message, MqttDeliveryEnvelope.Attempt("d".repeat(32), "mosquitto", 1))
        val before = sentCount()
        assertThrows(IllegalArgumentException::class.java) {
            routes.publishStoredReceipt(binding.scope, frame, "wrong", message.contentHash, binding.identity)
        }
        assertThrows(IllegalArgumentException::class.java) {
            routes.publishStoredReceipt(binding.scope, frame, "inbound", "e".repeat(64), binding.identity)
        }
        assertEquals(before, sentCount())
        routes.publishStoredReceipt(binding.scope, frame, "inbound", message.contentHash, binding.identity)
        assertEquals(before + 1, sentCount())
        val sent = rig.client("mosquitto").sent.last()
        val receipt = JSONObject(String(sent.message.payload, Charsets.UTF_8))
        assertFalse(receipt.has(MqttDeliveryEnvelope.FIELD))
        assertEquals(frame, MqttDeliveryEnvelope.parseVerifiedReceipt(receipt, binding.receiver, binding.sender))
    }

    @Test fun resumeUsesEveryReadyBootstrapPathButBusinessWaitsForAck() {
        start()
        assertTrue(rig.clients.values.all { it.first().sent.size == 1 })
        assertFalse(routes.ready(binding.scope))
        assertNull(routes.classify("outbox", byteArrayOf(1)))
        receive(ack())
        assertTrue(routes.ready(binding.scope))
        assertNotNull(routes.classify("outbox", byteArrayOf(1)))
    }

    @Test fun businessUsesOnlyRemoteAuthenticatedReceiveSet() {
        start()
        receive(ack())
        rig.transport.publish("outbox", org.eclipse.paho.client.mqttv3.MqttMessage(byteArrayOf(1)).apply { qos = 1 })
        assertEquals(2, rig.client("hivemq").sent.size)
        assertEquals(1, rig.client("emqx").sent.size)
        assertEquals(1, rig.completed.size)
    }

    @Test fun forgedAckCannotPersistOrGrantBusinessReadiness() {
        start()
        assertThrows(IllegalArgumentException::class.java) { receive(ack().put("acknowledged_digest", "0".repeat(64))) }
        assertTrue(store.recorded.isEmpty())
        assertFalse(routes.ready(binding.scope))
        assertThrows(IllegalArgumentException::class.java) { receive(ack().put("acknowledged_route_epoch", "1")) }
        assertTrue(store.recorded.isEmpty())
    }

    @Test fun authenticatedResumeCannotCrossPairIdentity() {
        start()
        assertThrows(IllegalArgumentException::class.java) {
            routes.handleVerified(binding.scope, ack(), rig.ingress("hivemq"), binding.identity.dropLast(1) + "d".repeat(43))
        }
        assertTrue(store.recorded.isEmpty())
    }

    @Test fun ackDoesNotProduceAckOfAckAndDuplicateDoesNotExtendExpiry() {
        start()
        val response = ack()
        val before = sentCount()
        receive(response)
        receive(response)
        assertEquals(before, sentCount())
        rig.wall.addAndGet(MqttBrokerCatalog.RESUME_TTL_MS)
        rig.clock.addAndGet(MqttBrokerCatalog.RESUME_TTL_MS)
        assertFalse(routes.ready(binding.scope))
        assertThrows(IllegalArgumentException::class.java) { receive(response) }
    }

    @Test fun duplicateRequestAckIsRateLimitedPerIngress() {
        start()
        val request = remote().toWire()
        val before = sentCount()
        receive(request)
        receive(request)
        assertEquals(before + 1, sentCount())
        rig.clock.addAndGet(1_000)
        receive(request)
        assertEquals(before + 2, sentCount())
    }

    @Test fun aSecondPairCannotBorrowFirstPairsReadiness() {
        val second = binding.copy(scope = "second", receiver = "d".repeat(64), secret = "e".repeat(43),
            sendTopic = "second-out", sendTopics = setOf("second-out"), receiveTopics = setOf("second-in"))
        start(listOf(binding, second))
        receive(ack())
        assertTrue(routes.readyForTopic("outbox"))
        assertFalse(routes.readyForTopic("second-out"))
        receive(ack(second), second)
        assertTrue(routes.readyForTopic("second-out"))
    }

    @Test fun pendingPairMayAuthenticateButCannotPublishBusinessUntilApproved() {
        val pending = binding.copy(enabled = false)
        start(listOf(pending))
        receive(ack(pending), pending)
        assertFalse(routes.readyForTopic("outbox"))
        routes.replace(listOf(binding))
        assertTrue(routes.readyForTopic("outbox"))
        routes.replace(listOf(pending))
        assertNull(routes.classify("outbox", byteArrayOf(1)))
    }

    @Test fun reconnectOfSameBrokerRequiresFreshLocalEpochAck() {
        start()
        receive(ack())
        val oldAck = ack()
        val oldEpoch = store.issued.getValue(binding.scope).epoch
        val old = rig.client("hivemq")
        old.lose()
        rig.await { rig.transport.readyPathGenerations(binding.receiveTopics)["hivemq"] == 2L }
        assertFalse(routes.ready(binding.scope))
        routes.maintenance()
        assertTrue(store.issued.getValue(binding.scope).epoch > oldEpoch)
        assertThrows(IllegalArgumentException::class.java) { receive(oldAck) }
        receive(ack())
        assertTrue(routes.ready(binding.scope))
    }

    @Test fun lateOldConnectionAckCannotMakeNewGenerationReady() {
        start()
        val response = ack()
        val oldIngress = rig.ingress("hivemq")
        rig.client("hivemq").lose()
        rig.await { rig.transport.readyPathGenerations(binding.receiveTopics)["hivemq"] == 2L }
        routes.handleVerified(binding.scope, response, oldIngress, binding.identity)
        assertTrue(store.recorded.isEmpty())
        assertFalse(routes.ready(binding.scope))
    }

    @Test fun revokedPairRejectsFrozenClassificationAndReplacementNeedsNewResume() {
        start()
        receive(ack())
        routes.replace(emptyList())
        assertFalse(routes.anyReady())
        assertNull(routes.classify("outbox", byteArrayOf(1)))
        assertEquals(listOf(binding.scope), store.forgotten)
        routes.replace(listOf(binding.copy(secret = "z".repeat(43))))
        assertFalse(routes.ready(binding.scope))
    }

    @Test fun invalidRegistryBatchDoesNotRemoveExistingAuthorizedPeer() {
        start()
        receive(ack())
        assertThrows(IllegalArgumentException::class.java) {
            routes.replace(listOf(binding, binding.copy(scope = "duplicate-outbound")))
        }
        assertTrue(routes.ready(binding.scope))
        assertTrue(store.forgotten.isEmpty())
    }

    @Test fun tenThousandPeersUseBoundedFairMaintenanceWithoutPerPeerThreads() {
        val many = (0 until 10_000).map { binding.copy(scope = "p$it", sendTopic = "out$it", sendTopics = setOf("out$it")) }
        start(many)
        assertEquals(16, store.issued.size)
        repeat(624) { routes.maintenance() }
        assertEquals(10_000, store.issued.size)
        assertEquals(3, rig.clients.values.sumOf { it.size })
    }
}
