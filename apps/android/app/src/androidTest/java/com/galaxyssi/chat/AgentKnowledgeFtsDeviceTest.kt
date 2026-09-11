package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.os.SystemClock
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentKnowledgeFtsDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun item(id: String, text: String, source: String = "source") = AgentKnowledgeItem(
        id = id, kind = AgentKnowledgeKind.NOTE, title = id, content = text, source = source)

    @Test fun bundledEngineActuallySupportsFts5AndIndexesOnlyKeyedTokens() = isolated { store, db ->
        store.upsert(item("private-title-marker", "confidentialbodymarker \u624b\u673a\u5185\u5b58"))
        db.access { sql ->
            sql.rawQuery("SELECT sqlite_compileoption_used('ENABLE_FTS5')", null).use {
                assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0))
            }
            sql.rawQuery("SELECT title,summary,body FROM knowledge_fts", null).use {
                assertTrue(it.moveToFirst())
                for (column in 0..2) assertTrue(it.getString(column).split(' ').all { token ->
                    token.matches(Regex("[0-9a-f]{64}"))
                })
            }
        }
        assertEquals("private-title-marker", store.search("\u5185\u5b58", 8).single().id)
    }

    @Test fun selectiveSearchDoesNotDecryptTheWholeThousandItemCorpus() = isolated { store, db ->
        store.replaceSource("source", (1..1200).map { item("record-$it", "ordinary background material $it") } +
            item("exact-match", "quartzneedle krypton") )
        val before = db.decryptedItemReads
        val start = SystemClock.elapsedRealtime()
        assertEquals("exact-match", store.search("quartzneedle", 8).single().id)
        val elapsed = SystemClock.elapsedRealtime() - start
        val reads = db.decryptedItemReads - before
        assertEquals(1, reads)
        println("KNOWLEDGE_FTS corpus=1201 decrypted=$reads elapsed_ms=$elapsed")
        val samples = LongArray(100) {
            val readStart = db.decryptedItemReads
            val started = SystemClock.elapsedRealtime()
            assertEquals("exact-match", store.search("quartzneedle", 8).single().id)
            assertEquals(1, db.decryptedItemReads - readStart)
            SystemClock.elapsedRealtime() - started
        }.sorted()
        println("KNOWLEDGE_FTS_HOT samples=100 p50_ms=${samples[49]} p95_ms=${samples[94]} p99_ms=${samples[98]}")
        assertTrue("Selective hot retrieval P95 exceeds 500 ms: ${samples[94]}", samples[94] < 500)
        assertEquals(1201, store.stats().itemCount)
    }

    @Test fun supportsChineseEnglishAndLateDocumentEvidence() = isolated { store, _ ->
        store.upsert(item("photo", "\u624b\u673a\u7167\u7247\u4fdd\u5b58\u5728\u672c\u5730\u76f8\u518c"))
        store.upsert(item("camera", "The CAMERA opens with a hardware button"))
        store.upsert(item("long", (1..100).joinToString(" ") { "prefix$it" } + " uniquetailmarker"))
        store.upsert(item("mixed", "\u4f7f\u7528Kotlin\u5f00\u53d1"))
        store.upsert(item("width", "\uFF26\uFF35\uFF2C\uFF2C\uFF37\uFF29\uFF24\uFF34\uFF28"))
        assertEquals("photo", store.search("\u7167\u7247", 8).first().id)
        assertEquals("camera", store.search("camera", 8).first().id)
        assertEquals("long", store.search("uniquetailmarker", 8).single().id)
        assertEquals("mixed", store.search("kotlin", 8).single().id)
        assertEquals("width", store.search("fullwidth", 8).single().id)
    }

    @Test fun replacementRollbackAndDeleteKeepIndexAtomic() = isolated { store, db ->
        store.upsert(item("old", "quartznebula"))
        db.access { it.execSQL("CREATE TRIGGER fail_fts BEFORE INSERT ON knowledge_fts_rows " +
            "BEGIN SELECT RAISE(ABORT,'test index failure'); END") }
        assertThrows(Exception::class.java) { store.replaceSource("source", listOf(item("new", "cobaltplanet"))) }
        assertEquals("old", store.search("quartznebula", 8).single().id)
        assertEquals(1, store.stats().itemCount)
        db.access { it.execSQL("DROP TRIGGER fail_fts") }
        store.replaceSource("source", listOf(item("new", "cobaltplanet")))
        assertTrue(store.search("quartznebula", 8).isEmpty())
        assertEquals("new", store.search("cobaltplanet", 8).single().id)
        assertEquals(1, store.delete("cobaltplanet"))
        db.access { sql ->
            for (table in listOf("knowledge_items", "knowledge_fts", "knowledge_fts_rows", "knowledge_fts_pending"))
                sql.rawQuery("SELECT count(*) FROM $table", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
    }

    @Test fun v1DatabaseBackfillsAndResumesAfterHelperReopen() {
        val name = "test-knowledge-fts-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        try {
            var store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
            store.replaceSource("source", (1..80).map { item("legacy-$it", "backfillevidence $it") })
            store.close()
            KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { sql ->
                KnowledgeVectorChangeFixtureSchema.remove(sql)
                sql.execSQL("DROP TRIGGER knowledge_fts_delete")
                sql.execSQL("DROP TABLE knowledge_fts")
                sql.execSQL("DROP TABLE knowledge_fts_pending")
                sql.execSQL("DROP TABLE knowledge_fts_rows")
                sql.execSQL("DROP TRIGGER knowledge_vector_source_insert")
                sql.execSQL("DROP TABLE knowledge_vector_queue")
                sql.execSQL("DROP TABLE knowledge_vectors")
                sql.execSQL("DROP TABLE knowledge_vector_docs")
                sql.execSQL("DROP TABLE knowledge_vector_models")
                for (operation in listOf("insert", "update", "delete")) sql.execSQL("DROP TRIGGER knowledge_browse_$operation")
                sql.execSQL("DROP INDEX IF EXISTS knowledge_source_recent")
                sql.execSQL("DROP TABLE knowledge_browse_revision")
                sql.execSQL("PRAGMA user_version=1")
            }
            store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
            assertEquals(80, store.stats().itemCount)
            store.close()
            store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
            val db = AgentKnowledgeDatabase.shared(context, name, legacy)
            val deadline = SystemClock.elapsedRealtime() + 60_000
            while (db.access { AgentKnowledgeFtsIndex.pending(it, 1).isNotEmpty() }) {
                check(SystemClock.elapsedRealtime() < deadline) { "FTS backfill did not complete: ${db.indexFailure}" }
                Thread.sleep(25)
            }
            assertEquals(24, store.search("backfillevidence", 24).size)
            assertEquals(80, store.stats().itemCount)
            db.access { sql -> sql.rawQuery("SELECT count(*) FROM knowledge_fts", null).use {
                assertTrue(it.moveToFirst()); assertEquals(80, it.getInt(0))
            } }
        } finally {
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }

    private fun isolated(block: (SQLiteAgentKnowledgeStore, AgentKnowledgeDatabase) -> Unit) {
        val name = "test-knowledge-fts-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        try {
            block(SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }, AgentKnowledgeDatabase.shared(context, name, legacy))
        } finally {
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }
}
