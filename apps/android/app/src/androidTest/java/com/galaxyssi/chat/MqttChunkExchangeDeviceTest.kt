package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MqttChunkExchangeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val routes = GalaxySSILinkProtocol.Routes(GalaxySSILinkProtocol.newRouteId(), GalaxySSILinkProtocol.newLinkSecret(),
        "a".repeat(64), "b".repeat(64))
    private lateinit var rig: MqttChunkDeviceRig
    private val wire = JSONObject().put("scheme", "signal").put("from", "desktop").put("to", "phone")
        .put("protocol", GalaxySSILinkProtocol.NAME).put("version", GalaxySSILinkProtocol.VERSION).put("body", "x".repeat(700_000))
    private val raw get() = GalaxySSIMqttWireChunking.encode(wire.toString())
    private var deliveries = 0
    private val receipts = mutableListOf<String>()
    private val peer get() = rig.binding.scope
    private val database get() = GalaxySSILinkDeliveryStore.transportMetadataDatabase(context)
    private val inboundScope get() = MqttDeliveryEnvelope.receiptBinding(peer, routes.remoteFingerprint, routes.localFingerprint, routes.linkSecret)

    @Before fun start() { rig = MqttChunkDeviceRig(context, routes) }
    @After fun cleanup() {
        if (::rig.isInitialized) {
            GalaxySSILinkDeliveryStore.inbox(context).forget(peer)
            rig.close()
        }
    }
    private fun parts(): List<JSONObject> {
        val parsed = raw.map(::JSONObject)
        val chunk = MqttChunkManifest.parse(parsed.first())
        val query = MqttChunkReceipts.Query(chunk.transfer, chunk.manifestHash, chunk.count, MqttChunkReceipts.newRequest())
        return parsed.map { it.put(MqttChunkReceipts.FIELD, query.wire()) }
    }
    private fun commit(decoded: JSONObject, transfer: String) {
        deliveries++
        assertEquals(wire.toString(), decoded.toString())
        val payload = JSONObject().put("message_id", "synthetic").put("type", "text").put("content", "test")
        val digest = GalaxySSILinkCiphertextReplayPolicy.digest(decoded)
        val inbox = GalaxySSILinkDeliveryStore.inbox(context)
        val accepted = inbox.accept(GalaxySSILinkInbox.Peer(peer, "desktop", false), "synthetic", MqttImmutableContent.hash(payload),
            payload, digest, true, MqttDeliveryEnvelope.contentHash(decoded))
        AndroidMqttChunks.releaseStored(context, routes, transfer, digest)
        inbox.complete(accepted.payload)
    }
    private fun receive(payload: JSONObject, ingress: MqttBrokerPool.Ingress = rig.ingress(),
                        handler: (JSONObject, String) -> Unit = ::commit) {
        val encoded = GalaxySSILinkProtocol.sealWirePacket(payload.toString(), routes.linkSecret)
        val authenticated = rig.decode(encoded.toByteArray(Charsets.UTF_8))
        assertTrue(AndroidMqttChunks.receive(context, routes, authenticated, ingress, rig.peers, "desktop", "phone", handler, receipts::add))
    }

    @Test fun realAndroidPublisherPersistsMissingBitsAndChangesRetryPath() {
        val first = requireNotNull(AndroidMqttChunks.prepare(context, routes.up, raw, routes.linkSecret, rig.peers))
        rig.publish(first)
        assertEquals(2, rig.sent.size)
        val firstFrames = rig.sent.toList()
        val query = requireNotNull(MqttChunkReceipts.fromChunk(rig.decode(firstFrames[0].message.payload)))
        receive(query.response("d".repeat(32), 1, listOf(0)))
        rig.sent.clear()
        val next = requireNotNull(AndroidMqttChunks.prepare(context, routes.up, raw, routes.linkSecret, rig.peers))
        assertEquals(1, next.size)
        rig.publish(next)
        assertEquals(1, rig.decode(rig.sent.single().message.payload).getInt("chunk_index"))
        assertNotEquals(firstFrames[1].broker, rig.sent.single().broker)
        assertEquals(0, deliveries)
        assertTrue(receipts.isEmpty())
    }

    @Test fun allStoredSendsOnlySmallQueryAndDoesNotPretendBusinessAccepted() {
        val first = requireNotNull(AndroidMqttChunks.prepare(context, routes.up, raw, routes.linkSecret, rig.peers))
        val query = requireNotNull(MqttChunkReceipts.fromChunk(rig.decode(first.first().first.toByteArray())))
        receive(query.response("d".repeat(32), 2, listOf(0, 1)))
        val next = requireNotNull(AndroidMqttChunks.prepare(context, routes.up, raw, routes.linkSecret, rig.peers)).single()
        assertEquals(MqttChunkReceipts.PROBE, rig.decode(next.first.toByteArray()).getString("type"))
        assertTrue(next.first.length < 8192)
        assertEquals(0, deliveries)
        assertTrue(receipts.isEmpty())
    }

    @Test fun ingressCompletesOnceThenProbeRepeatsProofBackedReceipt() {
        val parts = parts()
        parts.forEach { receive(it) }
        assertEquals(1, deliveries)
        assertEquals(1, rig.sent.size)
        assertEquals("Aw==", rig.decode(rig.sent.last().message.payload).getString("stored_bitmap"))
        assertTrue(receipts.isEmpty())
        receive(requireNotNull(MqttChunkReceipts.fromChunk(parts[0])).wire())
        receive(parts[1])
        assertEquals(1, deliveries)
        assertEquals(listOf("synthetic", "synthetic"), receipts)
        assertTrue(MqttDurableChunks(database).storedIndices(inboundScope, parts[0].getString("transfer_id")).isEmpty())
    }

    @Test fun probeResumesFailedHandoffFromLocalBytes() {
        val parts = parts()
        receive(parts[0])
        assertThrows(IllegalStateException::class.java) { receive(parts[1], handler = { _, _ -> error("Signal handoff unavailable") }) }
        assertEquals(0, deliveries)
        receive(requireNotNull(MqttChunkReceipts.fromChunk(parts[0])).wire())
        assertEquals(1, deliveries)
        assertTrue(receipts.isEmpty())
    }

    @Test fun staleGenerationWrongEndpointsAndRevocationCannotAdvanceTransfer() {
        val parts = parts()
        receive(parts[0], rig.ingress().copy(generation = 0))
        assertTrue(rig.sent.isEmpty())
        assertThrows(IllegalArgumentException::class.java) { receive(JSONObject(parts[0].toString()).put("from", "intruder")) }
        assertTrue(MqttDurableChunks(database).storedIndices(inboundScope, parts[0].getString("transfer_id")).isEmpty())
        rig.peers.replace(emptyList())
        receive(parts[0])
        assertTrue(rig.sent.isEmpty())
        assertNull(AndroidMqttChunks.prepare(context, routes.up, raw, routes.linkSecret, rig.peers))
        assertEquals(0, deliveries)
    }

    @Test fun completedChunkProofWithoutInboxProofCannotAcknowledgeBusiness() {
        val parts = parts()
        val receiver = MqttDurableChunks(database)
        parts.forEach { receiver.accept(inboundScope, it) }
        receiver.releaseAfterStore(inboundScope, parts[0].getString("transfer_id"), MqttDeliveryEnvelope.contentHash(wire), "absent")
        receive(requireNotNull(MqttChunkReceipts.fromChunk(parts[0])).wire())
        assertEquals(1, rig.sent.size)
        assertTrue(receipts.isEmpty())
        assertEquals(0, deliveries)
    }

    @Test fun partialStateWaitsForBoundedWindowButProbeDoesNot() {
        val parts = parts()
        receive(parts[0])
        assertTrue(rig.sent.isEmpty())
        Thread.sleep(MqttBrokerCatalog.CHUNK_FEEDBACK_WINDOW_MS + 20)
        rig.peers.maintenance()
        assertEquals("AQ==", rig.decode(rig.sent.single().message.payload).getString("stored_bitmap"))
        receive(requireNotNull(MqttChunkReceipts.fromChunk(parts[0])).wire())
        assertEquals(2, rig.sent.size)
        assertEquals(0, deliveries)
    }
}
