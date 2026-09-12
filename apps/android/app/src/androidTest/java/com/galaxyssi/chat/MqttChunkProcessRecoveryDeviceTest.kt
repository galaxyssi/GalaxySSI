package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Two explicit invocations separated by force-stop of the disposable verification package. */
@RunWith(AndroidJUnit4::class)
class MqttChunkProcessRecoveryDeviceTest {
    @Test fun partialWireSurvivesActualProcessStop() {
        val phase = InstrumentationRegistry.getArguments().getString("chunkRecoveryPhase").orEmpty()
        assumeTrue(phase in setOf("prepare", "verify"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        require(context.packageName == "com.galaxyssi.chat.mqttverification")
        val database = AgentEncryptedDatabase(context, "test_link_atomic_chunk_process_recovery")
        database.indexedTransaction { db ->
            db.rawQuery("PRAGMA synchronous", null).use { assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0)) }
            db.rawQuery("PRAGMA journal_mode", null).use { assertTrue(it.moveToFirst()); assertEquals("wal", it.getString(0)) }
        }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("chunk_recovery_phase", phase)
            putString("chunk_recovery_pid", android.os.Process.myPid().toString())
        })
        val store = MqttDurableChunks(database)
        val wire = JSONObject().put("scheme", "signal").put("from", "phone").put("to", "desktop").put("body", "x".repeat(700_000)).toString()
        val parts = GalaxySSIMqttWireChunking.encode(wire).map(::JSONObject)
        val transfer = parts.first().getString("transfer_id")
        val sender = MqttOutgoingChunks(database)
        if (phase == "prepare") {
            assertTrue(store.storedIndices("isolated-pair", transfer).isEmpty())
            assertNull(store.accept("isolated-pair", parts[0]))
            val batch = sender.prepare("isolated-outgoing", parts)
            sender.recordPath("isolated-outgoing", batch.query, 1, "emqx")
            assertTrue(sender.accept("isolated-outgoing", store.snapshot("isolated-pair", batch.query).state))
        } else {
            assertEquals(listOf(0), store.storedIndices("isolated-pair", transfer))
            val batch = sender.prepare("isolated-outgoing", parts)
            assertEquals(listOf(1), batch.selected.map { it.first })
            assertEquals(setOf("emqx"), batch.attempted(1))
            assertEquals(wire, store.accept("isolated-pair", parts[1]))
            assertTrue(store.releaseAfterStore("isolated-pair", transfer, MqttDeliveryEnvelope.contentHash(JSONObject(wire))))
            database.indexedTransaction { it.execSQL("DROP TABLE mqtt_outgoing_chunks") }
        }
    }
}
