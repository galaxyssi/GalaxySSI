package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentPersonalMemoryRowsDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }

    private fun legacy(f: MemoryDeletionDeviceFixture, items: List<AgentMemoryItem>): String =
        JSONArray().apply { items.forEach { put(f.store.encodeMemoryItem(it)) } }.toString()

    private fun ciphertext(f: MemoryDeletionDeviceFixture, id: String): String = f.sql().use { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key = ?",
            arrayOf(AgentPersonalMemoryRows.key(id))).use { cursor -> check(cursor.moveToFirst()); cursor.getString(0) }
    }

    @Test fun legacyMigrationPreservesMoreThanOneThousandItemsWithoutAGiantRow() = fixture { f ->
        val items = (0 until 1_201).map { deletionMemory(it) }
        f.store.database.writeString(AgentMemoryStorage.ITEMS, legacy(f, items))
        val start = SystemClock.elapsedRealtime()
        assertEquals(1_201, f.reopen().count())
        val migrated = SystemClock.elapsedRealtime()
        assertEquals(items, f.reopen().loadItems())
        val loaded = SystemClock.elapsedRealtime()
        repeat(20) { assertEquals(1_201, f.reopen().count()) }
        Log.i("GalaxySSIMemoryRowsTest", "rows=1201 migrationMs=${migrated-start} readMs=${loaded-migrated} count20Ms=${SystemClock.elapsedRealtime()-loaded}")
        assertFalse(f.store.database.contains(AgentMemoryStorage.ITEMS))
        assertEquals(1_201, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
    }

    @Test fun migrationFailureRetainsOriginalAndRollsBackEveryNewRow() = fixture { f ->
        val original = legacy(f, listOf(deletionMemory(1), deletionMemory(2)))
        f.store.database.writeString(AgentMemoryStorage.ITEMS, original)
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_rows_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key = 'personal-memory:v3:metadata' " +
                "BEGIN SELECT RAISE(ABORT, 'test_rows_abort'); END")
            try {
                assertNotNull(runCatching { f.reopen().loadItems() }.exceptionOrNull())
                assertEquals(original, f.store.database.readString(AgentMemoryStorage.ITEMS, ""))
                assertEquals(0, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
                assertFalse(f.store.database.contains(AgentPersonalMemoryRows.META))
            } finally { sql.execSQL("DROP TRIGGER test_rows_abort") }
        }
        assertEquals(2, f.reopen().count())
    }

    @Test fun malformedLegacyCannotBeSilentlyReplacedWithEmptyMemory() = fixture { f ->
        f.store.database.writeString(AgentMemoryStorage.ITEMS, "broken-json")
        assertNotNull(runCatching { f.reopen().count() }.exceptionOrNull())
        assertNotNull(runCatching { f.store.saveItems(listOf(deletionMemory(1))) }.exceptionOrNull())
        assertEquals("broken-json", f.store.database.readString(AgentMemoryStorage.ITEMS, ""))
        assertFalse(f.store.database.contains(AgentPersonalMemoryRows.META))
    }

    @Test fun duplicateLegacyIdentityCannotOverwriteOneOfTheMemories() = fixture { f ->
        val raw = legacy(f, listOf(deletionMemory(1), deletionMemory(1, "different")))
        f.store.database.writeString(AgentMemoryStorage.ITEMS, raw)
        assertNotNull(runCatching { f.reopen().count() }.exceptionOrNull())
        assertEquals(raw, f.store.database.readString(AgentMemoryStorage.ITEMS, ""))
        assertEquals(0, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
    }

    @Test fun editingOneFlagAndDeletingAnotherRowDoesNotRewriteSurvivingCiphertext() = fixture { f ->
        f.store.saveItems((0 until 12).map { deletionMemory(it) })
        val unchanged = ciphertext(f, "memory-10")
        val changed = ciphertext(f, "memory-1")
        assertTrue(f.store.setImportant("memory-1", true))
        assertEquals(unchanged, ciphertext(f, "memory-10"))
        assertNotEquals(changed, ciphertext(f, "memory-1"))
        assertTrue(f.store.deleteById("memory-0"))
        assertEquals(unchanged, ciphertext(f, "memory-10"))
        assertEquals((1 until 12).map { "memory-$it" }, f.reopen().loadItems().map { it.id })
    }

    @Test fun rowCountAndOrderingCorruptionFailClosed() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        val key = AgentPersonalMemoryRows.key("memory-2")
        val original = f.store.database.readString(key, "")
        f.store.database.writeString(key, JSONObject(original).put("position", 0).toString())
        assertNotNull(runCatching { f.reopen().loadItems() }.exceptionOrNull())
        f.store.database.remove(key)
        assertNotNull(runCatching { f.reopen().loadItems() }.exceptionOrNull())
    }

    @Test fun encryptedRowCannotBeReadAsAnotherIdentity() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val row = JSONObject(f.store.database.readString(key, ""))
        row.getJSONObject("item").put("id", "different")
        f.store.database.writeString(key, row.toString())
        assertNotNull(runCatching { f.reopen().loadItems() }.exceptionOrNull())
    }

    @Test fun metadataCountIncludesNormalizedSingletonConflictButExcludesHistory() = fixture { f ->
        val originals = listOf(deletionMemory(1).copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "old"),
            deletionMemory(2).copy(status = AgentMemoryStatus.SUPERSEDED), deletionMemory(3))
        f.store.database.writeString(AgentMemoryStorage.ITEMS, legacy(f, originals))
        assertEquals(2, f.reopen().count())
        assertEquals(2, f.reopen().snapshot().activeItems.size)
        assertEquals(1, f.reopen().snapshot().historyItems.size)
    }

    @Test fun failedReplacementRestoresEarlierRowsAndMetadata() = fixture { f ->
        val original = listOf(deletionMemory(1), deletionMemory(2))
        f.store.saveItems(original)
        val metadata = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        val first = ciphertext(f, "memory-1")
        assertNotNull(runCatching { f.store.saveItems(listOf(deletionMemory(1, "changed"), deletionMemory(1))) }.exceptionOrNull())
        assertEquals(first, ciphertext(f, "memory-1"))
        assertEquals(metadata, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        assertEquals(original, f.reopen().loadItems())
    }

    @Test fun independentInstancesSeeTheCommittedReplacementWithoutSnapshotStaleness() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val other = f.reopen()
        assertEquals(1, other.count())
        assertEquals("memory-1", other.loadItems().single().id)
        f.store.saveItems(listOf(deletionMemory(2), deletionMemory(3)))
        assertEquals(2, other.count())
        assertEquals(listOf("memory-2", "memory-3"), other.loadItems().map { it.id })
    }
}
