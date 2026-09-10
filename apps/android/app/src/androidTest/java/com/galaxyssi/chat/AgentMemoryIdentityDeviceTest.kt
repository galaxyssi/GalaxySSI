package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryIdentityDeviceTest {
    private fun memory(id: String, scopeId: String = "conversation-a", value: String = "\u5317\u4eac") =
        AgentMemoryItem(AgentMemoryKind.PREFERENCE, value, id = id, key = "city",
            scope = AgentMemoryScope.CONVERSATION, scopeId = scopeId)

    private fun withStore(block: (EncryptedAgentMemoryStore, () -> EncryptedAgentMemoryStore) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val prefix = "test-memory-identity-${UUID.randomUUID()}-"
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getDatabasePath(name: String): File =
                if (File(name).isAbsolute) File(name) else base.getDatabasePath(prefix + name)
            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
                base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
                errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
                base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
            override fun getSharedPreferences(name: String, mode: Int) = base.getSharedPreferences(prefix + name, mode)
        }
        fun open() = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
        val store = open()
        try { block(store, ::open) } finally {
            store.database.clear()
            AgentEncryptedDatabase(context, EncryptedAgentMemoryDeletionIndex.DATABASE_NAME).clear()
        }
    }

    @Test fun persistedScopeTypeAndIdentifierMatrixDoesNotDeduplicate() = withStore { store, reopen ->
        val expected = mutableSetOf<String>()
        AgentMemoryScope.entries.forEach { scope ->
            listOf("Case", "case").forEach { scopeId ->
                val id = "${scope.name}-$scopeId"
                expected.add(id)
                assertFalse(store.remember(memory(id, scopeId).copy(scope = scope)).duplicate)
            }
        }
        val snapshot = reopen().snapshot()
        assertEquals(expected, snapshot.activeItems.map { it.id }.toSet())
        assertTrue(snapshot.conflicts.isEmpty())
    }

    @Test fun editingAndDeletingPersistOnlyTheSelectedNamespace() = withStore { store, reopen ->
        store.remember(memory("a"))
        store.remember(memory("b", "conversation-b"))
        val edited = store.update("a", "\u73e0\u6d77")!!.item!!
        assertTrue(store.deleteById(edited.id))
        val next = reopen()
        assertEquals(listOf("b"), next.snapshot().activeItems.map { it.id })
        assertTrue(next.snapshot().historyItems.isEmpty())
        val deleted = next.deletionIndex.snapshot().flatMap { it.memoryIds }.toSet()
        assertEquals(setOf("a", edited.id), deleted)
        assertEquals(listOf("b"), AgentMemoryCausalDeletionPolicy.filterRestoredItems(
            listOf(memory("a"), memory("b", "conversation-b")), next.deletionIndex.snapshot()).map { it.id })
    }

    @Test fun legacyMixedGroupsAreMigratedBeforeReadingAndRemainSeparateAfterWrite() = withStore { store, reopen ->
        val original = listOf(memory("a1"), memory("a2", value = "\u73e0\u6d77"),
            memory("b1", "conversation-b"), memory("b2", "conversation-b", "\u4e0a\u6d77"),
            memory("single", "conversation-c"))
            .map { it.copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "legacy-group") }
        // Bypass the new writer to exercise the actual legacy encrypted storage path.
        store.database.writeString("items", JSONArray().apply {
            original.forEach { put(store.encodeMemoryItem(it)) }
        }.toString())
        val snapshot = reopen().snapshot()
        assertEquals(listOf("single"), snapshot.activeItems.map { it.id })
        assertEquals(2, snapshot.conflicts.size)
        val groupA = snapshot.conflicts.single { it.candidates.any { row -> row.id == "a1" } }
        assertNotNull(store.resolveConflict(groupA.groupId, "a2", null))
        val after = reopen().snapshot()
        assertEquals(2, after.activeItems.size)
        assertEquals(setOf("b1", "b2"), after.conflicts.single().candidates.map { it.id }.toSet())
        assertEquals(setOf("a1", "a2"), after.historyItems.map { it.id }.toSet())
        assertEquals(0, reopen().decodeItems(store.database.readString("items", "[]"))
            .count { it.conflictGroupId == "legacy-group" && it.status == AgentMemoryStatus.CONFLICTED })
    }

    @Test fun foreignLineageCannotDeleteOrTombstoneAnotherConversation() = withStore { store, reopen ->
        store.saveItems(listOf(
            memory("a").copy(supersedesId = "foreign"),
            memory("new").copy(supersedesId = "a", key = "renamed"),
            memory("foreign", "conversation-b").copy(supersedesId = "a")
        ))
        store.deleteById("a")
        assertEquals(listOf("foreign"), reopen().snapshot().activeItems.map { it.id })
        assertFalse(reopen().deletionIndex.snapshot().any { "foreign" in it.memoryIds })
    }

    @Test fun moreThanOneThousandActiveNamespacesSurviveMutationAndReopen() = withStore { store, reopen ->
        val originals = (0 until 1_201).map { memory("item-$it", "conversation-$it") }
        store.saveItems(originals)
        assertEquals(1_201, reopen().count())
        assertTrue(store.deleteById("item-600"))
        val actual = reopen().snapshot().activeItems
        assertEquals(originals.filterNot { it.id == "item-600" }.toSet(), actual.toSet())
        assertEquals(setOf("item-600"), reopen().deletionIndex.snapshot().flatMap { it.memoryIds }.toSet())
    }

    @Test fun sameScopeConflictAndDuplicateEvidenceStillPersist() = withStore { store, reopen ->
        store.remember(memory("a").copy(evidenceCount = 2))
        assertTrue(store.remember(memory("duplicate").copy(evidenceCount = 3)).duplicate)
        assertEquals(5, reopen().snapshot().activeItems.single().evidenceCount)
        val conflict = store.remember(memory("b", value = "\u73e0\u6d77")).conflict!!
        assertNotNull(store.resolveConflict(conflict.groupId, "b", "\u4e0a\u6d77"))
        assertEquals("\u4e0a\u6d77", reopen().snapshot().activeItems.single().value)
        assertEquals(2, reopen().snapshot().historyItems.size)
    }

    @Test fun unmatchedQueryCannotDeleteRecentHighConfidenceMemories() = withStore { store, reopen ->
        val first = memory("a").copy(important = true, confidence = 1.0, evidenceCount = 100)
        val second = memory("b", "conversation-b", "\u73e0\u6d77")
        store.remember(first)
        store.remember(second)
        val unrelated = "\u706b\u5c71"
        assertTrue(store.score(first, unrelated) > 0.0)
        assertEquals(0.0, store.lexicalScore(first, unrelated), 0.0)
        assertEquals(0, store.delete(unrelated))
        assertEquals(setOf("a", "b"), reopen().snapshot().activeItems.map { it.id }.toSet())
        assertTrue(reopen().deletionIndex.snapshot().isEmpty())
        assertEquals(1, store.delete("\u5317\u4eac"))
        assertEquals(listOf("b"), reopen().snapshot().activeItems.map { it.id })
        assertEquals(setOf("a"), reopen().deletionIndex.snapshot().flatMap { it.memoryIds }.toSet())
    }

    @Test fun unmatchedQueryIsNotRecalledButMatchingValueAndKeyStillWork() = withStore { store, _ ->
        store.remember(memory("a"))
        store.remember(memory("b", "conversation-b", "\u73e0\u6d77"))
        assertTrue(store.recall("\u706b\u5c71").isEmpty())
        assertEquals(listOf("b"), store.recall("\u73e0\u6d77").map { it.id })
        assertEquals(setOf("a", "b"), store.recall("city").map { it.id }.toSet())
    }
}
