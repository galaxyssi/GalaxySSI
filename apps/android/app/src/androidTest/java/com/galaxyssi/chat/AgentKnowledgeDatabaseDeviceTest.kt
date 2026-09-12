package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentKnowledgeDatabaseDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun item(index: Int, source: String = "source") = AgentKnowledgeItem(id = "item-$index",
        kind = AgentKnowledgeKind.NOTE, title = "Record $index", content = "Private knowledge item $index",
        source = source, updatedAtMillis = index.toLong())

    @Test fun moreThanFiveHundredItemsSurviveReopenWithoutEviction() = isolated { name, legacy ->
        var store = store(name, legacy)
        store.replaceSource("source", (1..1_200).map { item(it) })
        assertEquals(1_200L, store.stats().itemCount)
        store.upsert(item(1_201, "other"))
        store.close()
        store = store(name, legacy)
        assertEquals(1_201L, store.stats().itemCount)
        assertEquals(2L, store.stats().sourceCount)
        assertEquals(1_201L, store.stats().lastUpdatedAtMillis)
        assertEquals(setOf("item-1", "item-1201"), store.findByIds(setOf("item-1", "item-1201")).map { it.id }.toSet())
        assertEquals(1_201, store.list(2_000).size)
        assertEquals(10, store.list(10).size)
        assertEquals(60, store.searchRanked("", 60).size)
        assertEquals("item-1201", store.list(1).single().id)
    }

    @Test fun legacyMigrationKeepsContentsAndPoliciesThenRemovesOnlyLegacyArray() = isolated { name, legacy ->
        val original = (1..12).map { item(it).copy(cloudAccess = AgentKnowledgeCloudAccess.SUMMARY_ONLY,
            agentAccess = AgentKnowledgeAgentAccess.SELECTED_AGENTS, allowedAgentIds = listOf("trusted")) }
        val preferences = AgentEncryptedPreferences(context, legacy)
        preferences.writeString("items", JSONArray().also { a -> original.forEach { a.put(AgentKnowledgeCodec.encodeItem(it)) } }.toString())
        preferences.writeString("unrelated", "keep")
        val store = store(name, legacy)
        assertEquals(12L, store.stats().itemCount)
        assertEquals(original.map { it.copy(summary = AgentKnowledgeCodec.summarize(it.content)) }.toSet(),
            store.list(20).toSet())
        assertFalse(preferences.keys().contains("items"))
        assertEquals("keep", preferences.readString("unrelated", ""))
        store.close()
        assertEquals(12L, store(name, legacy).stats().itemCount)
    }

    @Test fun malformedLegacyDataDoesNotCommitAnEmptyMigration() = isolated { name, legacy ->
        val preferences = AgentEncryptedPreferences(context, legacy)
        preferences.writeString("items", "not-json")
        assertThrows(Exception::class.java) { store(name, legacy).stats() }
        assertEquals("not-json", preferences.readString("items", ""))
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_meta", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
    }

    @Test fun wrongCiphertextCannotSilentlyEraseLegacyKnowledge() = isolated { name, legacy ->
        context.getSharedPreferences(legacy, 0).edit().putString("items", "invalid-ciphertext").commit()
        assertThrows(Exception::class.java) { store(name, legacy).stats() }
        assertTrue(context.getSharedPreferences(legacy, 0).contains("items"))
    }

    @Test fun largeUnicodeItemIsEncryptedInSegmentsWithBoundedSqlReference() = isolated { name, legacy ->
        val expected = item(1).copy(content = ("\u79c1\u5bc6\u77e5\u8bc6\uD83D\uDE80" + "z".repeat(15)).repeat(60_000))
        val store = store(name, legacy)
        store.upsert(expected)
        assertEquals(expected.content, store.findByIds(setOf(expected.id)).single().content)
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_chunks", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            }
            db.rawQuery("SELECT count(*),max(length(reference)) FROM knowledge_primary_refs", null).use {
                assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)); assertTrue(it.getInt(1) <= 2048)
            }
            db.rawQuery("SELECT count(*) FROM knowledge_items WHERE header LIKE '%Private%' OR title_key LIKE '%Record%' OR source_key='source'", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            }
        }
    }

    @Test fun failedReplacementRollsBackOldSourceAndPublishesNoMutation() = isolated { name, legacy ->
        var mutations = 0
        val store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> mutations++ }
        store.upsert(item(1))
        mutations = 0
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { db ->
            db.execSQL("CREATE TRIGGER reject_new_chunks BEFORE INSERT ON knowledge_primary_refs BEGIN SELECT RAISE(ABORT,'test storage failure'); END")
        }
        assertThrows(Exception::class.java) { store.replaceSource("source", listOf(item(2))) }
        assertEquals(listOf("item-1"), store.list(5).map { it.id })
        assertEquals(0, mutations)
    }

    @Test fun sourceReplacementRetainsPolicyAndDeletionRemovesChunks() = isolated { name, legacy ->
        val store = store(name, legacy)
        store.upsert(item(1).copy(cloudAccess = AgentKnowledgeCloudAccess.DENY))
        store.updateAccess(setOf("item-1"), AgentKnowledgeCloudAccess.FULL,
            AgentKnowledgeAgentAccess.SELECTED_AGENTS, listOf("trusted"))
        store.replaceSource("source", listOf(item(2).copy(content = "uniqueerasemarker")))
        val next = store.list(1).single()
        assertEquals(AgentKnowledgeCloudAccess.FULL, next.cloudAccess)
        assertEquals(listOf("trusted"), next.allowedAgentIds)
        assertEquals(1, store.searchRanked("uniqueerasemarker", 8).size)
        assertEquals(1, store.delete("uniqueerasemarker"))
        assertEquals(0L, store.stats().itemCount)
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_chunks", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
    }

    @Test fun backupRoundTripIsCompleteAndInvalidRestoreRollsBack() = isolated { name, legacy ->
        val store = store(name, legacy)
        store.replaceSource("source", (1..601).map { item(it) })
        val backup = store.exportJson()
        assertEquals(601, backup.length())
        store.replaceAllJson(JSONArray())
        assertEquals(0L, store.stats().itemCount)
        store.replaceAllJson(backup)
        assertEquals(601L, store.stats().itemCount)
        assertThrows(Exception::class.java) { store.replaceAllJson(JSONArray().put("invalid")) }
        assertEquals(601L, store.stats().itemCount)
        assertEquals("item-1", store.findByIds(setOf("item-1")).single().id)
    }

    @Test fun alteredIndexCannotReturnAnUnauthenticatedItem() = isolated { name, legacy ->
        val store = store(name, legacy)
        store.upsert(item(1))
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { it.execSQL("UPDATE knowledge_items SET updated=999") }
        assertThrows(Exception::class.java) { store.findByIds(setOf("item-1")) }
    }

    @Test fun missingChunkIsNotTreatedAsMissingKnowledge() = isolated { name, legacy ->
        val store = store(name, legacy)
        store.upsert(item(1))
        KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { it.execSQL("DELETE FROM knowledge_primary_refs") }
        assertThrows(Exception::class.java) { store.findByIds(setOf("item-1")) }
        assertEquals(1L, store.stats().itemCount)
    }

    @Test fun replacementCannotStealAnotherSourcesId() = isolated { name, legacy ->
        val store = store(name, legacy)
        store.upsert(item(1, "first"))
        store.upsert(item(2, "second"))
        assertThrows(IllegalArgumentException::class.java) {
            store.replaceSource("second", listOf(item(1, "second")))
        }
        assertEquals(setOf("first", "second"), store.list(10).map { it.source }.toSet())
        assertEquals(2L, store.stats().itemCount)
    }

    private fun store(name: String, legacy: String) = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
    private fun isolated(block: (String, String) -> Unit) {
        val name = "test-knowledge-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        try { block(name, legacy) } finally {
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }
}
