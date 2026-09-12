package com.galaxyssi.chat

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class MqttDurableChunksDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val database by lazy { AgentEncryptedDatabase(context, "test_link_atomic_chunks_${UUID.randomUUID()}") }
    private var now = 1_000_000L
    private val wire = JSONObject().put("scheme", "signal").put("from", "phone").put("to", "desktop").put("body", "x".repeat(700_000)).toString()
    private val parts = GalaxySSIMqttWireChunking.encode(wire).map(::JSONObject)
    private val transfer = parts.first().getString("transfer_id")
    private fun store(maxTransfers: Int = 16, maxPeerTransfers: Int = 8) =
        MqttDurableChunks(database, now = { now }, maxTransfers = maxTransfers, maxPeerTransfers = maxPeerTransfers)

    @Before fun verifyProductionDurabilitySettings() {
        database.indexedTransaction { db ->
            db.rawQuery("PRAGMA synchronous", null).use { assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0)) }
            db.rawQuery("PRAGMA journal_mode", null).use { assertTrue(it.moveToFirst()); assertEquals("wal", it.getString(0)) }
        }
    }

    @After fun cleanup() {
        database.indexedTransaction { db ->
            db.execSQL("DROP TABLE IF EXISTS mqtt_wire_parts")
            db.execSQL("DROP TABLE IF EXISTS mqtt_wire_transfers")
        }
    }

    @Test fun recreatedStoreKeepsPartialAndCompleteDataUntilVerifiedHandoff() {
        assertNull(store().accept("pair", parts[1]))
        assertEquals(listOf(1), store().storedIndices("pair", transfer))
        assertEquals(wire, store().accept("pair", parts[0]))
        assertEquals(wire, store().accept("pair", parts[1]))
        assertEquals(listOf(0, 1), store().storedIndices("pair", transfer))
    }

    @Test fun concurrentCopiesUseOneDatabaseRowAndOneQuotaReservation() {
        val store = store()
        val executor = Executors.newFixedThreadPool(3)
        try {
            val results = (0 until 12).map { executor.submit<String?> { store.accept("pair", parts[0]) } }
            results.forEach { assertNull(it.get(30, TimeUnit.SECONDS)) }
            database.indexedTransaction { db ->
                db.rawQuery("SELECT COUNT(*) FROM mqtt_wire_parts", null).use { assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)) }
            }
            assertEquals(wire, store.accept("pair", parts[1]))
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun pairAndKeyScopesCannotMixSameTransfer() {
        val store = store()
        store.accept("pair-old-key", parts[0])
        assertNull(store.accept("pair-new-key", parts[1]))
        assertNull(store.accept("other-pair", parts[1]))
        assertEquals(wire, store.accept("pair-old-key", parts[1]))
    }

    @Test fun invalidFirstCopyCannotReserveStorage() {
        val store = store()
        assertThrows(IllegalArgumentException::class.java) { store.accept("pair", JSONObject(parts[0].toString()).put("data", "aW52YWxpZA==")) }
        assertTrue(store.storedIndices("pair", transfer).isEmpty())
        assertNull(store.accept("pair", parts[0]))
    }

    @Test fun conflictingDuplicateDoesNotReplaceValidBytes() {
        val store = store()
        store.accept("pair", parts[0])
        val data = Base64.decode(parts[0].getString("data"), Base64.NO_WRAP).apply { this[0] = 'y'.code.toByte() }
        val changed = JSONObject(parts[0].toString()).put("data", Base64.encodeToString(data, Base64.NO_WRAP))
            .put("chunk_sha256", GalaxySSIMqttWireChunking.sha256(data))
        assertThrows(IllegalArgumentException::class.java) { store.accept("pair", changed) }
        assertEquals(wire, store.accept("pair", parts[1]))
    }

    @Test fun fullHashFailureRollsBackLastChunkSoValidRetryCanFinish() {
        val store = store()
        store.accept("pair", parts[0])
        val data = Base64.decode(parts[1].getString("data"), Base64.NO_WRAP).apply { this[lastIndex] = '!'.code.toByte() }
        val changed = JSONObject(parts[1].toString()).put("data", Base64.encodeToString(data, Base64.NO_WRAP))
            .put("chunk_sha256", GalaxySSIMqttWireChunking.sha256(data))
        assertThrows(IllegalArgumentException::class.java) { store.accept("pair", changed) }
        assertEquals(listOf(0), store.storedIndices("pair", transfer))
        assertEquals(wire, store.accept("pair", parts[1]))
    }

    @Test fun geometryConflictCannotReplaceManifest() {
        val store = store()
        store.accept("pair", parts[0])
        assertThrows(IllegalArgumentException::class.java) {
            store.accept("pair", JSONObject(parts[1].toString()).put("total_bytes", parts[1].getInt("total_bytes") + 1))
        }
        assertEquals(wire, store.accept("pair", parts[1]))
    }

    @Test fun corruptedStoredBytesAreRejectedThenRepairedOnlyWithMatchingHash() {
        val store = store()
        store.accept("pair", parts[0])
        database.indexedTransaction { it.execSQL("UPDATE mqtt_wire_parts SET data=?", arrayOf("corrupt".toByteArray())) }
        assertThrows(IllegalArgumentException::class.java) { store.accept("pair", parts[1]) }
        assertNull(store.accept("pair", parts[0]))
        assertEquals(wire, store.accept("pair", parts[1]))
    }

    @Test fun capacityNeverEvictsAnAcceptedPartial() {
        val store = store(maxTransfers = 1)
        store.accept("pair", parts[0])
        assertThrows(IllegalArgumentException::class.java) { store.accept("other", parts[1]) }
        assertEquals(wire, store.accept("pair", parts[1]))
        assertFalse(store.releaseAfterStore("pair", transfer, "f".repeat(64)))
        assertTrue(store.releaseAfterStore("pair", transfer, MqttDeliveryEnvelope.contentHash(JSONObject(wire))))
        assertNull(store.accept("other", parts[0]))
    }

    @Test fun perPeerQuotaLeavesRoomForOtherPairs() {
        val store = store(maxPeerTransfers = 1)
        store.accept("pair", parts[0])
        val changed = GalaxySSIMqttWireChunking.encode(wire.replace("phone", "other")).first()
        assertThrows(IllegalArgumentException::class.java) { store.accept("pair", JSONObject(changed)) }
        assertNull(store.accept("other-pair", parts[0]))
    }

    @Test fun duplicateTrafficCannotExtendFixedRetentionForever() {
        val store = store()
        store.accept("pair", parts[0])
        now += MqttDurableChunks.RETENTION_MILLIS - 1
        store.accept("pair", parts[0])
        now += 2
        assertTrue(store.storedIndices("pair", transfer).isEmpty())
        assertNull(store.accept("pair", parts[1]))
        assertEquals(listOf(1), store.storedIndices("pair", transfer))
    }

    @Test fun malformedCounterTypesAndOversizedEncodingAreRejected() {
        val store = store()
        for ((key, value) in listOf("chunk_index" to "0", "chunk_index" to false, "chunk_count" to 0,
            "total_bytes" to Long.MAX_VALUE, "data" to "x".repeat(600_000), "transfer_id" to "G".repeat(64))) {
            assertThrows(IllegalArgumentException::class.java) { store.accept("pair", JSONObject(parts[0].toString()).put(key, value)) }
        }
    }

    @Test fun actualAndroidHandoffRequiresCommittedInboxWireProof() {
        val routes = GalaxySSILinkProtocol.Routes(GalaxySSILinkProtocol.newRouteId(), GalaxySSILinkProtocol.newLinkSecret(), "a".repeat(64), "b".repeat(64))
        val scope = MqttDeliveryEnvelope.receiptBinding(GalaxySSILinkDeliveryStore.peerScope(routes), routes.remoteFingerprint, routes.localFingerprint, routes.linkSecret)
        val actualStore = MqttDurableChunks(GalaxySSILinkDeliveryStore.transportMetadataDatabase(context))
        val digest = GalaxySSILinkCiphertextReplayPolicy.digest(JSONObject(wire))
        parts.forEach { AndroidMqttChunks.accept(context, routes, it) }
        AndroidMqttChunks.releaseStored(context, routes, transfer, digest)
        assertEquals(listOf(0, 1), actualStore.storedIndices(scope, transfer))
        val inbox = GalaxySSILinkDeliveryStore.inbox(context)
        val peer = GalaxySSILinkInbox.Peer(GalaxySSILinkDeliveryStore.peerScope(routes), "phone", true)
        val payload = JSONObject().put("message_id", "synthetic").put("type", "text").put("content", "test")
        val accepted = inbox.accept(peer, "synthetic", MqttImmutableContent.hash(payload), payload, digest, true,
            MqttDeliveryEnvelope.contentHash(JSONObject(wire)))
        AndroidMqttChunks.releaseStored(context, routes, transfer, digest)
        assertTrue(actualStore.storedIndices(scope, transfer).isEmpty())
        inbox.complete(accepted.payload)
        inbox.forget(peer.scope)
    }
}
