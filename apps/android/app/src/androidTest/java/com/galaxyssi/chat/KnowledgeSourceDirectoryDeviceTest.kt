package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceDirectoryDeviceTest {
    @Test fun emptyDirectoryTracksLiveSourcesAndLocalNotesImmediately() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create(); assertTrue(f.state().complete)
        f.put(1); f.put(2, ""); f.put(3, ""); f.verify()
        assertEquals(3L, f.state().groups); assertEquals(1L, f.state().namedGroups)
    }
    @Test fun migrationIsBoundedAndDoesNotBuildAnIndexOverOldSources() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.transaction { (1..137).forEach { f.put(it) } }; f.create()
        assertEquals(0L, f.state().items); assertFalse(f.state().complete)
        assertThrows(KnowledgeSourceDirectoryNotReady::class.java) { f.state().requireReady() }
        assertFalse(f.page()); assertEquals(64L, f.state().items)
        assertFalse(f.page()); assertEquals(128L, f.state().items)
        assertTrue(f.page()); f.verify()
    }
    @Test fun editsOnBothSidesOfCursorRemainExact() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.transaction { (1..137).forEach { f.put(it) } }; f.create(); f.page()
        f.put(1, f.key(100)); f.put(100, ""); f.put(0); f.put(200)
        f.transaction { f.db.delete("knowledge_items", "item_key IN (?,?)", arrayOf(f.key(2), f.key(101))) }
        f.finish(); f.verify(); assertEquals(137L, f.state().items)
    }
    @Test fun deletingLatestTiedAndLastMembersUpdatesTheHead() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create(); f.put(1, f.key(9), 100); f.put(2, f.key(9), 100); f.put(3, f.key(9), 99)
        for (id in 1..3) {
            f.db.rawQuery("SELECT head FROM knowledge_source_directory", null).use { assertTrue(it.moveToFirst()); assertEquals(f.key(id), it.getString(0)) }
            f.transaction { f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(id))) }; f.verify()
        }
        assertEquals(0L, f.state().groups)
    }
    @Test fun updateMovesSourceGroupAndTimestampAtomically() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create(); f.put(1); f.put(2)
        f.transaction { f.db.rawQuery("UPDATE knowledge_items SET source_key=?,updated=? WHERE item_key=?",
            arrayOf(f.key(2), "999", f.key(1))).use { it.moveToNext() } }
        f.verify(); assertEquals(1L, f.state().groups)
    }
    @Test fun rollbackRestoresMembersCountsAndCheckpoint() = KnowledgeSourceDirectoryTestFixture().use { f ->
        (1..8).forEach { f.put(it) }; f.create()
        assertThrows(IllegalStateException::class.java) { f.transaction { f.page(3); f.put(50); error("rollback") } }
        assertEquals(0L, f.state().items); assertEquals("", f.state().after)
        f.finish(); f.verify(); assertEquals(8L, f.state().items)
    }
    @Test fun ignoredCheckpointRollsBackEnrolledRows() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.put(1); f.create()
        f.db.execSQL("CREATE TRIGGER ignore_source_cursor BEFORE UPDATE OF after_item ON knowledge_source_state BEGIN SELECT RAISE(IGNORE); END")
        assertThrows(IllegalStateException::class.java) { f.page() }
        assertEquals(0L, f.state().items)
        f.db.execSQL("DROP TRIGGER ignore_source_cursor"); f.finish(); f.verify()
    }
    @Test fun missingStateRejectsLiveWritesInsteadOfRecreatingCounters() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create(); f.db.execSQL("DELETE FROM knowledge_source_state")
        assertThrows(Exception::class.java) { f.put(1) }
        f.db.rawQuery("SELECT 1 FROM knowledge_items", null).use { assertFalse(it.moveToFirst()) }
    }
    @Test fun invalidCursorCannotSilentlyRestartEnrollment() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.put(1); f.create(); f.db.execSQL("UPDATE knowledge_source_state SET after_item='invalid'")
        assertThrows(IllegalStateException::class.java) { f.page() }
        Unit
    }
    @Test fun reopenContinuesCommittedCursorAndVerifiesAllGroups() = KnowledgeSourceDirectoryTestFixture().use { f ->
        (1..137).forEach { f.put(it) }; f.create(); f.page()
        val cursor = f.state().after; f.reopen(); assertEquals(cursor, f.state().after)
        f.finish(); f.verify()
    }
    @Test fun tupleSeekHandlesTiesAndLongTimestampExtremes() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create(); f.transaction { (1..130).forEach { f.put(it, updated = 5) } }
        f.put(131, updated = Long.MIN_VALUE); f.put(132, updated = Long.MAX_VALUE)
        val seen = linkedSetOf<String>(); var sort = Long.MIN_VALUE; var group = ""
        do {
            var count = 0
            f.db.rawQuery(KnowledgeSourceDirectory.BROWSE_SQL, arrayOf(sort.toString(), group, "7")).use { c ->
                while (c.moveToNext()) {
                    group = c.getString(0); sort = c.getLong(1).inv(); count++
                    assertTrue(seen.add(group))
                }
            }
        } while (count > 0)
        assertEquals(132, seen.size); assertEquals("s:${f.key(132)}", seen.first()); assertEquals("s:${f.key(131)}", seen.last())
        f.verify()
    }
    @Test fun queryPlansSeekExistingIndexesWithoutAggregationOrTempSort() = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.create()
        for ((sql, args) in listOf(KnowledgeSourceDirectory.PAGE_SQL to arrayOf(f.key(500), "65"),
            KnowledgeSourceDirectory.BROWSE_SQL to arrayOf("-500", "s:${f.key(500)}", "51"))) {
            val plan = f.db.rawQuery("EXPLAIN QUERY PLAN $sql", args).use { c -> buildList { while (c.moveToNext()) add(c.getString(3)) }.joinToString(" ") }
            assertTrue(plan, plan.contains("SEARCH")); assertFalse(plan, plan.contains("TEMP B-TREE")); assertFalse(plan, plan.contains("SCAN "))
        }
    }
}
