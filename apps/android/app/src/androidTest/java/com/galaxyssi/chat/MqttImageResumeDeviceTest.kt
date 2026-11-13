package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.After
import java.util.UUID

class MqttImageResumeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val databases = mutableListOf<AgentEncryptedDatabase>()
    private fun database(label: String) = AgentEncryptedDatabase(context, "test_image_${label}_${UUID.randomUUID()}").also(databases::add)
    @After fun cleanup() {
        databases.forEach { database -> database.indexedTransaction { db ->
            for (table in listOf("mqtt_outgoing_chunks", "mqtt_wire_parts", "mqtt_wire_transfers"))
                db.execSQL("DROP TABLE IF EXISTS $table")
        } }
    }
    private fun wire() = JSONObject().put("scheme", "signal").put("from", "phone")
        .put("to", "desktop").put("body", "x".repeat(470_000)).toString()

    @Test fun directMessagesLeaveReadinessToDeliveryDispatch() {
        val value = JSONObject().put("scheme", "signal").put("from", "phone")
            .put("to", "desktop").put("body", "small").toString()
        assertEquals(listOf(value), AndroidMqttChunks.encode(context, "unused", value, "unused", null))
    }

    @Test fun receiverAdmitsAFullFileWindowAlongsidePartialTransfers() {
        val receiver = MqttDurableChunks(database("window"))
        val windows = (0 until 24).map { index ->
            MqttWireSizingPolicy.encode(JSONObject(wire()).put("sequence", index).toString()).map(::JSONObject)
        }
        windows.forEach { assertNull(receiver.accept("pair", it.first())) }
        windows.forEach { parts ->
            assertEquals(listOf(0), receiver.storedIndices("pair", parts.first().getString("transfer_id")))
        }
        var complete: String? = null
        windows.last().drop(1).forEach { complete = receiver.accept("pair", it) }
        assertEquals(23, JSONObject(requireNotNull(complete)).getInt("sequence"))
    }

    @Test fun missingFragmentsAndPathsSurviveStoreRecreation() {
        val database = database("resume")
        val value = wire()
        val parts = MqttWireSizingPolicy.encode(value).map(::JSONObject)
        val sender = MqttOutgoingChunks(database)
        val receiver = MqttDurableChunks(database)
        val first = sender.prepare("pair", parts)
        first.selected.take(3).forEach { (index, payload) ->
            sender.recordPath("pair", first.query, index, "emqx")
            receiver.accept("pair", payload)
        }
        val state = receiver.snapshot("pair", first.query).state
        assertTrue(sender.accept("pair", state))
        val restored = MqttOutgoingChunks(database)
        assertEquals(MqttWireSizingPolicy.CHUNK_BYTES, restored.chunkDataBytes("pair", first.query.transfer))
        val second = restored.prepare("pair", MqttWireSizingPolicy.encode(value,
            restored.chunkDataBytes("pair", first.query.transfer)).map(::JSONObject))
        assertEquals((3 until parts.size).toList(), second.selected.map { it.first })
        var result: String? = null
        second.selected.reversed().forEach { (_, payload) -> result = receiver.accept("pair", payload) }
        assertEquals(value, result)
        assertTrue(restored.accept("pair", receiver.snapshot("pair", second.query).state))
        val probeOnly = restored.prepare("pair", parts)
        assertEquals(listOf(-1), probeOnly.selected.map { it.first })
    }

    @Test fun retryChangesPathWithoutChangingCiphertext() {
        val database = database("paths")
        val sender = MqttOutgoingChunks(database)
        val parts = MqttWireSizingPolicy.encode(wire()).map(::JSONObject)
        val first = sender.prepare("pair", parts)
        sender.recordPath("pair", first.query, 0, "emqx")
        val retry = MqttOutgoingChunks(database).prepare("pair", parts)
        assertEquals(setOf("emqx"), retry.attempted(0))
        assertTrue(retry.attempted(1).isEmpty())
        assertEquals(first.selected.first().second.getString("data"), retry.selected.first().second.getString("data"))
        assertFalse(sender.accept("other-pair", first.query.response("e".repeat(32), 1, listOf(0))))
    }

    @Test fun legacyMetadataMigrationKeepsPartiallyReceivedLargeLayout() {
        val database = database("layout")
        database.indexedTransaction { db ->
            db.execSQL("""CREATE TABLE mqtt_outgoing_chunks (
                scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, manifest_hash TEXT NOT NULL,
                chunk_count INTEGER NOT NULL, request_id TEXT NOT NULL, store_epoch TEXT NOT NULL,
                revision INTEGER NOT NULL, stored_bitmap BLOB NOT NULL, path_bits BLOB NOT NULL,
                expires_at INTEGER NOT NULL, PRIMARY KEY(scope_digest,transfer_id))""")
            db.execSQL("INSERT INTO mqtt_outgoing_chunks VALUES(?,?,?,?,?,'',-1,?,?,?)",
                arrayOf(MqttDurableChunks.scopeKey("pair"), "a".repeat(64), "b".repeat(64), 2,
                    "c".repeat(32), byteArrayOf(1), byteArrayOf(1, 0), Long.MAX_VALUE))
        }
        val migrated = MqttOutgoingChunks(database)
        assertEquals(MqttChunkManifest.DATA_BYTES, migrated.chunkDataBytes("pair", "a".repeat(64)))
        database.indexedTransaction { db ->
            db.rawQuery("SELECT stored_bitmap,path_bits FROM mqtt_outgoing_chunks", null).use {
                assertTrue(it.moveToFirst())
                assertArrayEquals(byteArrayOf(1), it.getBlob(0))
                assertArrayEquals(byteArrayOf(1, 0), it.getBlob(1))
            }
        }
    }
}
