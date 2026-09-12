package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeIdentityDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun note(id: String, source: String = "source-$id", title: String = "Shared title") =
        AgentKnowledgeItem(id = id, kind = AgentKnowledgeKind.NOTE, title = title,
            source = source, content = "identitymarker$id", updatedAtMillis = 123L)

    @Test fun sameTitlePreservesBothSourcesPoliciesAndSearchResults() = isolated { store, _, _ ->
        store.upsert(note("alpha").copy(cloudAccess = AgentKnowledgeCloudAccess.DENY))
        store.upsert(note("beta").copy(cloudAccess = AgentKnowledgeCloudAccess.FULL))
        assertEquals(2L, store.stats().itemCount)
        assertEquals("alpha", store.search("identitymarkeralpha", 1).single().id)
        assertEquals("beta", store.search("identitymarkerbeta", 1).single().id)
        assertEquals(AgentKnowledgeCloudAccess.DENY, store.findByIds(setOf("alpha")).single().cloudAccess)
        assertEquals(AgentKnowledgeCloudAccess.FULL, store.findByIds(setOf("beta")).single().cloudAccess)
        assertTrue(AgentKnowledgeRetriever.retrieve(store, "identitymarkeralpha", "cloud-models").citations.none { it.itemId == "alpha" })
    }

    @Test fun titlesAndCaseCannotDeleteAnotherIdentityEvenWithinOneSource() = isolated { store, _, _ ->
        store.upsert(note("alpha", "shared"))
        store.upsert(note("beta", "shared", "SHARED TITLE"))
        store.upsert(note("gamma", "shared"))
        store.upsert(note("alpha", "shared", "SHARED TITLE").copy(content = "replacementmarker"))
        assertEquals(3L, store.stats().itemCount)
        assertEquals(setOf("alpha", "beta", "gamma"), store.list(10).map { it.id }.toSet())
        assertEquals("replacementmarker", store.findByIds(setOf("alpha")).single().content)
        assertEquals("identitymarkerbeta", store.findByIds(setOf("beta")).single().content)
    }

    @Test fun sourceOwnershipAndBlankIdsAreRejectedWithoutMutations() = isolated { store, _, events ->
        store.upsert(note("owned"))
        events.clear()
        assertThrows(IllegalArgumentException::class.java) { store.upsert(note("owned", "other")) }
        assertThrows(IllegalArgumentException::class.java) { store.upsert(note("owned", "")) }
        assertThrows(IllegalArgumentException::class.java) { store.upsert(note("  ")) }
        assertEquals("source-owned", store.findByIds(setOf("owned")).single().source)
        assertEquals(1L, store.stats().itemCount)
        assertTrue(events.isEmpty())
    }

    @Test fun exactReplayPreservesEncryptedVectorCheckpointAndEmitsNoEvent() = isolated { store, db, events ->
        val original = note("replay")
        store.upsert(original)
        val spec = KnowledgeVectorSpec("a".repeat(64), 4, 128)
        val encoder = object : KnowledgeVectorEncoder {
            override val spec = spec
            override fun tokenCount(text: String) = text.length
            override fun embed(text: String) = floatArrayOf(1f, 0f, 0f, 0f)
            override fun close() = Unit
        }
        store.indexVectorChunks(encoder, 8)
        val before = checkpoint(db)
        events.clear()
        repeat(12) { store.upsert(original) }
        assertEquals(before, checkpoint(db))
        assertTrue(events.isEmpty())
        assertNull(db.vectors(spec).nextJob())
        assertEquals(1L, store.stats().itemCount)
    }

    @Test fun failedIdentityUpdateRollsBackAndKeepsSameNamedPeer() = isolated { store, db, events ->
        store.upsert(note("alpha"))
        store.upsert(note("beta"))
        events.clear()
        db.transaction { it.execSQL("CREATE TRIGGER fail_identity_update BEFORE INSERT ON knowledge_primary_refs " +
            "BEGIN SELECT RAISE(ABORT,'injected identity write failure'); END") }
        assertThrows(Exception::class.java) { store.upsert(note("alpha").copy(content = "new content")) }
        assertEquals(2L, store.stats().itemCount)
        assertEquals("identitymarkeralpha", store.findByIds(setOf("alpha")).single().content)
        assertEquals("identitymarkerbeta", store.findByIds(setOf("beta")).single().content)
        assertTrue(events.isEmpty())
    }

    @Test fun sixHundredAndOneSameNamedSourcesSurviveIncrementalUpsertsAndReopen() = isolated { store, db, _ ->
        val started = android.os.SystemClock.elapsedRealtime()
        repeat(601) { store.upsert(note("entry$it")) }
        assertEquals(601L, store.stats().itemCount)
        assertEquals(601L, store.stats().sourceCount)
        val database = dbName(db)
        store.close()
        val reopened = SQLiteAgentKnowledgeStore(context, database, "legacy-$database") { _, _ -> }
        assertEquals(601L, reopened.stats().itemCount)
        assertEquals(601, reopened.exportJson().length())
        assertEquals("entry0", reopened.search("identitymarkerentry0", 1).single().id)
        assertEquals("entry600", reopened.search("identitymarkerentry600", 1).single().id)
        println("KNOWLEDGE_IDENTITY same_named_sources=601 preserved=601 elapsed_ms=" +
            (android.os.SystemClock.elapsedRealtime() - started))
    }

    private val names = mutableMapOf<AgentKnowledgeDatabase, String>()
    private fun dbName(db: AgentKnowledgeDatabase) = requireNotNull(names[db])
    private fun checkpoint(db: AgentKnowledgeDatabase): String = db.access {
        it.rawQuery("SELECT hex(ciphertext) FROM knowledge_vectors ORDER BY item_key,ordinal", null).use { c ->
            assertTrue(c.moveToFirst()); c.getString(0)
        }
    }
    private fun isolated(block: (SQLiteAgentKnowledgeStore, AgentKnowledgeDatabase,
        MutableList<Pair<List<AgentKnowledgeItem>, List<AgentKnowledgeItem>>>) -> Unit) {
        val name = "test-identity-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        val events = mutableListOf<Pair<List<AgentKnowledgeItem>, List<AgentKnowledgeItem>>>()
        val db = AgentKnowledgeDatabase.shared(context, name, legacy)
        names[db] = name
        try { block(SQLiteAgentKnowledgeStore(context, name, legacy) { before, after -> events += before to after }, db, events) }
        finally {
            names.remove(db)
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }
}
