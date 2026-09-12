package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class MqttChunkStateDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val database by lazy { AgentEncryptedDatabase(context, "test_link_atomic_chunk_state_${UUID.randomUUID()}") }
    private var now = 1_000_000L
    private val wire = JSONObject().put("scheme", "signal").put("from", "phone").put("to", "desktop").put("body", "x".repeat(700_000)).toString()
    private val parts = GalaxySSIMqttWireChunking.encode(wire).map(::JSONObject)
    private fun sender() = MqttOutgoingChunks(database, now = { now })
    private fun receiver() = MqttDurableChunks(database, now = { now })
    private fun begin() = sender().prepare("outbound", parts)
    private fun state(batch: MqttOutgoingChunks.Batch, indices: List<Int> = listOf(0), revision: Long = 1,
                      epoch: String = "a".repeat(32)) = batch.query.response(epoch, revision, indices)

    @Before fun verifyProductionDurabilitySettings() {
        database.indexedTransaction { db ->
            db.rawQuery("PRAGMA synchronous", null).use { assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0)) }
            db.rawQuery("PRAGMA journal_mode", null).use { assertTrue(it.moveToFirst()); assertEquals("wal", it.getString(0)) }
        }
    }
    @After fun cleanup() {
        database.indexedTransaction { db ->
            for (table in listOf("mqtt_outgoing_chunks", "mqtt_wire_parts", "mqtt_wire_transfers")) db.execSQL("DROP TABLE IF EXISTS $table")
        }
    }

    @Test fun recreatedSenderSelectsOnlyMissingIndices() {
        val batch = begin()
        assertEquals(listOf(0, 1), batch.selected.map { it.first })
        assertEquals(batch.query, MqttChunkReceipts.fromChunk(batch.selected[0].second))
        assertTrue(sender().accept("outbound", state(batch)))
        val resumed = begin()
        assertEquals(listOf(1), resumed.selected.map { it.first })
        assertNotEquals(batch.query.request, resumed.query.request)
    }

    @Test fun completeBitmapSendsOnlyProbeNotBusinessCompletion() {
        val batch = begin()
        sender().accept("outbound", state(batch, listOf(0, 1)))
        val probe = begin().selected.single()
        assertEquals(-1, probe.first)
        assertEquals(MqttChunkReceipts.PROBE, probe.second.getString("type"))
        assertTrue(probe.second.toString().length < 1024)
        assertFalse(probe.second.toString().contains("RX_STORED"))
    }

    @Test fun unsolicitedOldRoundAndOtherPairCannotAdvanceState() {
        val first = begin()
        assertFalse(sender().accept("other-pair", state(first)))
        val next = begin()
        assertFalse(sender().accept("outbound", state(first)))
        assertTrue(sender().accept("outbound", state(next)))
        assertEquals(listOf(1), begin().selected.map { it.first })
    }

    @Test fun olderAndConflictingRevisionCannotRollBack() {
        val batch = begin()
        assertTrue(sender().accept("outbound", state(batch, listOf(0, 1), 2)))
        assertFalse(sender().accept("outbound", state(batch, listOf(0), 1)))
        assertFalse(sender().accept("outbound", state(batch, listOf(0, 1), 2)))
        assertThrows(IllegalArgumentException::class.java) { sender().accept("outbound", state(batch, listOf(0), 2)) }
        assertEquals(-1, begin().selected.single().first)
    }

    @Test fun newerRevisionCanRetractCorruptionButNotChangeEpoch() {
        val batch = begin()
        sender().accept("outbound", state(batch, listOf(0, 1)))
        assertFalse(sender().accept("outbound", state(batch, emptyList(), 3, "b".repeat(32))))
        assertTrue(sender().accept("outbound", state(batch, listOf(1), 2)))
        assertEquals(listOf(0), begin().selected.map { it.first })
    }

    @Test fun newProbeRoundCanAcceptReceiverStorageReset() {
        val batch = begin()
        sender().accept("outbound", state(batch, listOf(0, 1)))
        val probe = begin()
        assertTrue(sender().accept("outbound", state(probe, emptyList(), 0, "0".repeat(32))))
        assertEquals(listOf(0, 1), begin().selected.map { it.first })
    }

    @Test fun actualPathAttemptsPersistAndStaleCallbackCannotChangeNewRound() {
        val batch = begin()
        sender().recordPath("outbound", batch.query, 1, "emqx")
        val next = begin()
        assertEquals(setOf("emqx"), next.attempted(1))
        assertTrue(next.attempted(0).isEmpty())
        sender().recordPath("outbound", batch.query, 1, "hivemq")
        sender().recordPath("outbound", next.query, 1, "mosquitto")
        assertEquals(setOf("emqx", "mosquitto"), begin().attempted(1))
    }

    @Test fun corruptedSnapshotRetractsOnlyDamagedBytesThenRepairs() {
        val batch = begin()
        val receiver = receiver()
        parts.forEach { receiver.accept("inbound", it) }
        database.indexedTransaction { it.execSQL("UPDATE mqtt_wire_parts SET data=? WHERE chunk_index=0", arrayOf("damaged".toByteArray())) }
        val snapshot = receiver.snapshot("inbound", batch.query)
        assertArrayEquals(byteArrayOf(2), MqttChunkReceipts.parseState(snapshot.state).bitmap)
        assertNull(receiver.recoverComplete("inbound", batch.query))
        assertEquals(wire, receiver.accept("inbound", parts[0]))
        assertEquals(wire, receiver.recoverComplete("inbound", batch.query))
    }

    @Test fun completedProofKeepsNoWireBytesAndCannotReadmitCopies() {
        val batch = begin()
        val receiver = receiver()
        parts.forEach { receiver.accept("inbound", it) }
        val hash = MqttDeliveryEnvelope.contentHash(JSONObject(wire))
        assertFalse(receiver.releaseAfterStore("inbound", batch.query.transfer, "f".repeat(64), "message"))
        assertTrue(receiver.releaseAfterStore("inbound", batch.query.transfer, hash, "message"))
        val snapshot = receiver.snapshot("inbound", batch.query)
        assertEquals("message" to hash, snapshot.proof)
        assertArrayEquals(byteArrayOf(3), MqttChunkReceipts.parseState(snapshot.state).bitmap)
        assertNull(receiver.recoverComplete("inbound", batch.query))
        parts.forEach { assertNull(receiver.accept("inbound", it)) }
        assertTrue(receiver.storedIndices("inbound", batch.query.transfer).isEmpty())
    }

    @Test fun unknownProbeAllocatesNoIncomingStorage() {
        val snapshot = receiver().snapshot("unknown", begin().query)
        assertArrayEquals(byteArrayOf(0), MqttChunkReceipts.parseState(snapshot.state).bitmap)
        database.indexedTransaction { db ->
            db.rawQuery("SELECT COUNT(*) FROM mqtt_wire_transfers", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
    }

    @Test fun retriesCannotExtendSenderRetention() {
        val batch = begin()
        sender().accept("outbound", state(batch))
        now += 7L * 86400 * 1000 - 1
        val nearExpiry = begin()
        assertEquals(listOf(1), nearExpiry.selected.map { it.first })
        now += 2
        assertFalse(sender().accept("outbound", state(nearExpiry)))
        assertEquals(listOf(0, 1), begin().selected.map { it.first })
    }

    @Test fun targetExpiryIsIndependentOfBoundedCleanupBacklog() {
        val batch = begin()
        sender().accept("outbound", state(batch))
        receiver().accept("inbound", parts[0])
        database.indexedTransaction { db ->
            repeat(300) { index ->
                val dummy = index.toString(16).padStart(64, '0')
                db.execSQL("INSERT INTO mqtt_outgoing_chunks SELECT scope_digest,?,manifest_hash,chunk_count,request_id,store_epoch,revision,stored_bitmap,path_bits,0 FROM mqtt_outgoing_chunks WHERE transfer_id=?",
                    arrayOf(dummy, batch.query.transfer))
                db.execSQL("INSERT INTO mqtt_wire_transfers SELECT scope_digest,?,manifest_hash,chunk_count,total_bytes,stored_bytes,0,wire_hash,source,target,store_epoch,revision,'completed' FROM mqtt_wire_transfers WHERE transfer_id=?",
                    arrayOf(dummy, batch.query.transfer))
            }
        }
        now += MqttDurableChunks.RETENTION_MILLIS + 1
        assertEquals(listOf(0, 1), begin().selected.map { it.first })
        assertNull(receiver().accept("inbound", parts[1]))
        assertEquals(listOf(1), receiver().storedIndices("inbound", batch.query.transfer))
    }
}
