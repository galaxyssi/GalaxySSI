package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePagingDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun item(id: Int, source: String = "source-$id") = AgentKnowledgeItem("source-item-$id",
        AgentKnowledgeKind.NOTE, "\u77e5\u8bc6\u6765\u6e90 $id", "private evidence $id", source = source,
        updatedAtMillis = (id / 3).toLong())

    @Test fun traverses1201SourcesWithTiesWithoutDecryptingBodies() = isolated { store, db, _ ->
        repeat(1201) { store.upsert(item(it)) }
        val before = db.decryptedItemReads
        val summaries = db.decryptedSourceSummaryReads
        val started = SystemClock.elapsedRealtime()
        val seen = linkedSetOf<String>()
        var cursor: AgentKnowledgeSourceCursor? = null
        var previousTime = Long.MAX_VALUE
        var pages = 0
        do {
            val page = store.sourcePage(cursor)
            assertEquals(1201, page.total)
            assertTrue(page.groups.size <= 50)
            page.groups.forEach { group ->
                assertTrue(group.updatedAtMillis <= previousTime)
                previousTime = group.updatedAtMillis
                assertTrue("Duplicate source ${group.source}", seen.add(group.source))
                assertTrue(group.itemIds.isEmpty())
                assertEquals(1, group.chunkCount)
            }
            cursor = page.next
            pages++
        } while (cursor != null)
        assertEquals(1201, seen.size)
        assertEquals(25, pages)
        assertEquals(before, db.decryptedItemReads)
        assertEquals(1201L, db.decryptedSourceSummaryReads - summaries)
        assertEquals(1201, store.sourceCount())
        println("KNOWLEDGE_SOURCE_PAGING sources=1201 pages=$pages body_reads=0 elapsed_ms=${SystemClock.elapsedRealtime() - started}")
    }

    @Test fun wholeSourceCountAndAccessResolveBeyond500WithoutEagerMemberReads() = isolated { store, db, _ ->
        store.replaceSource("long-source", (0..600).map { item(it, "long-source") })
        store.upsert(item(9999))
        val bodies = db.decryptedItemReads
        val summaries = db.decryptedSourceSummaryReads
        val page = store.sourcePage()
        assertEquals(2, page.total)
        val group = page.groups.single { it.source == "long-source" }
        assertEquals(601, group.chunkCount)
        assertEquals(2L, db.decryptedSourceSummaryReads - summaries)
        assertEquals(bodies, db.decryptedItemReads)
        val ids = store.sourceItemIds(requireNotNull(group.reference))
        assertEquals(601, ids.size)
        assertEquals(bodies, db.decryptedItemReads)
        assertEquals(601, store.updateAccess(ids, AgentKnowledgeCloudAccess.SUMMARY_ONLY,
            AgentKnowledgeAgentAccess.SELECTED_AGENTS, listOf("trusted-agent")))
        val ends = store.findByIds(setOf("source-item-0", "source-item-600"))
        assertTrue(ends.all { it.cloudAccess == AgentKnowledgeCloudAccess.SUMMARY_ONLY && it.allowedAgentIds == listOf("trusted-agent") })
        assertEquals(AgentKnowledgeCloudAccess.DENY, store.findByIds(setOf("source-item-9999")).single().cloudAccess)
    }

    @Test fun sameNamedLocalNotesRemainSeparateSourcesAndIdentityScoped() = isolated { store, _, _ ->
        store.upsert(item(1, "").copy(title = "Same"))
        store.upsert(item(2, "").copy(title = "Same"))
        val page = store.sourcePage()
        assertEquals(2, page.total)
        val members = page.groups.map { store.sourceItemIds(requireNotNull(it.reference)) }
        assertTrue(members.all { it.size == 1 })
        assertEquals(setOf("source-item-1", "source-item-2"), members.flatten().toSet())
    }

    @Test fun mutationsInvalidateCursorButExactReplayAndVectorWorkDoNot() = isolated { store, db, _ ->
        val notes = (0..2).map { item(it) }
        notes.forEach(store::upsert)
        val first = store.sourcePage(limit = 1)
        val cursor = requireNotNull(first.next)
        store.upsert(notes.first())
        db.vectors(KnowledgeVectorSpec("b".repeat(64), 4, 128)).nextJob()
        assertEquals(1, store.sourcePage(cursor, 1).groups.size)
        store.upsert(notes.last().copy(content = "changed content", updatedAtMillis = 1234))
        assertThrows(KnowledgeSourcePageChanged::class.java) { store.sourcePage(cursor) }
        val refreshed = store.sourcePage(limit = 1)
        assertEquals(notes.last().source, refreshed.groups.single().source)
        store.delete("changed content")
        assertThrows(KnowledgeSourcePageChanged::class.java) { store.sourcePage(requireNotNull(refreshed.next)) }
    }

    @Test fun cursorReopensAgainstSameDatabaseAndCannotCrossNamespaces() = isolated { store, _, name ->
        repeat(3) { store.upsert(item(it)) }
        val cursor = requireNotNull(store.sourcePage(limit = 1).next)
        store.close()
        val reopened = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        assertEquals(2, reopened.sourcePage(cursor).groups.size)
        isolated { other, _, _ ->
            other.upsert(item(1))
            assertThrows(IllegalArgumentException::class.java) { other.sourcePage(cursor) }
        }
        assertThrows(IllegalArgumentException::class.java) { reopened.sourcePage(limit = 0) }
        assertThrows(IllegalArgumentException::class.java) { reopened.sourcePage(limit = 51) }
        assertThrows(IllegalArgumentException::class.java) { reopened.sourcePage(cursor.copy(groupKey = "invalid")) }
    }

    @Test fun v3UpgradeReadsLegacyPreviewWithoutRewritingUserCiphertext() = isolated { store, db, name ->
        store.upsert(item(1))
        val key = db.key("id", "source-item-1")
        val aad = "$name:$key:header".toByteArray()
        val oldHeader = db.access { sql ->
            val encrypted = sql.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                assertTrue(it.moveToFirst()); it.getString(0)
            }
            val header = JSONObject(requireNotNull(AgentStorageCipher.decrypt(encrypted, aad)))
            header.remove("source_preview")
            val legacy = AgentStorageCipher.encrypt(header.toString(), aad)
            sql.rawQuery("UPDATE knowledge_items SET header=? WHERE item_key=?", arrayOf(legacy, key)).use { it.moveToNext() }
            for (operation in listOf("insert", "update", "delete")) sql.execSQL("DROP TRIGGER knowledge_browse_$operation")
            sql.execSQL("DROP INDEX knowledge_source_recent")
            sql.execSQL("DROP TABLE knowledge_browse_revision")
            sql.execSQL("PRAGMA user_version=3")
            legacy
        }
        val vectorSpec = KnowledgeVectorSpec("c".repeat(64), 4, 128)
        store.indexVectorChunks(object : KnowledgeVectorEncoder {
            override val spec = vectorSpec
            override fun tokenCount(text: String) = text.length
            override fun embed(text: String) = floatArrayOf(1f, 0f, 0f, 0f)
            override fun close() = Unit
        })
        val oldVector = db.access { sql -> sql.rawQuery("SELECT hex(ciphertext) FROM knowledge_vectors", null).use {
            assertTrue(it.moveToFirst()); it.getString(0)
        } }
        db.access(KnowledgeVectorChangeFixtureSchema::remove)
        store.close()
        val reopened = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val page = reopened.sourcePage()
        assertEquals(item(1).title, page.groups.single().title)
        assertEquals(setOf("source-item-1"), reopened.sourceItemIds(requireNotNull(page.groups.single().reference)))
        AgentKnowledgeDatabase.shared(context, name, "legacy-$name").access { sql ->
            sql.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                assertTrue(it.moveToFirst()); assertEquals(oldHeader, it.getString(0))
            }
            sql.rawQuery("PRAGMA user_version", null).use { assertTrue(it.moveToFirst()); assertEquals(7, it.getInt(0)) }
            sql.rawQuery("SELECT hex(ciphertext) FROM knowledge_vectors", null).use {
                assertTrue(it.moveToFirst()); assertEquals(oldVector, it.getString(0))
            }
        }
        requireNotNull(AgentKnowledgeDatabase.shared(context, name, "legacy-$name").vectors(vectorSpec).page("source-item-1"))
            .use { assertEquals(1, it.total) }
    }

    @Test fun corruptedPreviewCannotBeDisplayedAndEmptyCorpusIsTerminal() = isolated { store, db, _ ->
        assertNull(store.sourcePage().next)
        assertEquals(0, store.sourcePage().total)
        store.upsert(item(1))
        db.access { it.execSQL("UPDATE knowledge_items SET header='corrupt' ") }
        assertThrows(Exception::class.java) { store.sourcePage() }
    }

    private fun isolated(block: (SQLiteAgentKnowledgeStore, AgentKnowledgeDatabase, String) -> Unit) {
        val name = "test-source-pages-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        try { block(SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> },
            AgentKnowledgeDatabase.shared(context, name, legacy), name) }
        finally {
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }
}
