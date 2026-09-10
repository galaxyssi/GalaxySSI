package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentShadowRoutingIndexDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val names = mutableListOf<String>()
    private fun name() = "test-shadow-index-${UUID.randomUUID()}".also(names::add)
    @After fun cleanup() { names.forEach { AgentEncryptedDatabase(context, it).clear() } }

    private fun sample(id: String, at: Long) = AgentShadowRoutingRecommendation(
        id, "public-test", AgentEvalTaskClass.GENERAL, "codex", "codex", emptyList(), false, 0.5, at
    )
    private fun legacy(id: String, at: Long) = JSONObject()
        .put("id", id).put("scenario_id", "public-test").put("task_class", "general")
        .put("actual_resource_id", "codex").put("recommended_resource_id", "codex")
        .put("scores", JSONArray()).put("confidence", 0.5).put("created_at_millis", at).toString()

    @Test fun migratesFullLegacyHistoryAndKeepsTimestampOrderAcrossReopen() {
        val name = name()
        val database = AgentEncryptedDatabase(context, name)
        database.mutateStrings((0..519).associate { "recommendation:id-$it" to legacy("id-$it", it.toLong()) })
        val store = AgentShadowRoutingStore(context, name)
        assertEquals(listOf("id-519", "id-518"), store.recent(2).map { it.id })
        assertEquals(500, database.keys("recommendation:").size)
        assertEquals(500, store.recent().size)
        store.save(sample("late-arriving-old", -1))
        assertEquals(500, store.recent().size)
        assertFalse(database.contains("recommendation:late-arriving-old"))
        store.save(sample("id-20", 9999))
        val reopened = AgentShadowRoutingStore(context, name)
        assertEquals("id-20", reopened.recent(1).single().id)
        assertEquals(500, reopened.recent().map { it.id }.distinct().size)
        val index = requireNotNull(AgentShadowRoutingOrderIndex.decode(database.readString(AgentShadowRoutingOrderIndex.KEY, "")))
        assertEquals(database.keys("recommendation:").toSet(), index.map { it.key }.toSet())
        context.openOrCreateDatabase("$name.db", 0, null).use { raw ->
            raw.rawQuery("SELECT encrypted_value FROM encrypted_values", null).use { cursor ->
                while (cursor.moveToNext()) assertTrue(cursor.getString(0).startsWith("enc:v1:"))
            }
        }
    }

    @Test fun reconstructsCorruptIndexAndExternallyAddedLegacyRows() {
        val name = name()
        val database = AgentEncryptedDatabase(context, name)
        val store = AgentShadowRoutingStore(context, name)
        store.save(sample("first", 10))
        database.writeString(AgentShadowRoutingOrderIndex.KEY, "corrupt")
        assertEquals("first", store.recent(1).single().id)
        database.writeString("recommendation:second", legacy("second", 20))
        assertEquals(listOf("second", "first"), store.recent().map { it.id })
        database.remove("recommendation:second")
        assertEquals("first", store.recent(1).single().id)
    }

    @Test fun concurrentStoreInstancesCannotLoseOrderEntries() {
        val name = name()
        val workers = Executors.newFixedThreadPool(4)
        try {
            val tasks = (0 until 32).map { i -> workers.submit {
                AgentShadowRoutingStore(context, name).save(sample("concurrent-$i", i.toLong()))
            } }
            tasks.forEach { it.get(30, TimeUnit.SECONDS) }
            val values = AgentShadowRoutingStore(context, name).recent()
            assertEquals(32, values.size)
            assertEquals((31 downTo 0).map { "concurrent-$it" }, values.map { it.id })
        } finally { workers.shutdownNow() }
    }
}
