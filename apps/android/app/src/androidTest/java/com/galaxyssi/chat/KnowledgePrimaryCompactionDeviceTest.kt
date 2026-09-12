package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryCompactionDeviceTest {
    @Test fun partialLiveShardMovesInPagesAndResumesAfterReopen() {
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.seed()
            val source = f.source()
            val first = KnowledgePrimaryReclaim.advance(f.db, f.parts) { }
            assertEquals(8, first.movedRecords); assertFalse(first.complete)
            assertTrue(File(f.root, "$source.sqlite").isFile)
            f.verify()
            f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            assertEquals(8, f.drain()); f.verify()
            assertEquals(1, f.root.listFiles()!!.count { it.extension == "sqlite" })
            assertEquals(16L, f.number("SELECT count(*) FROM knowledge_primary_refs"))
        }
    }

    @Test fun cancellationRollsBackRelocatedPrefixAndCheckpoint() = KnowledgePrimaryCompactionFixture().use { f ->
        f.seed(); val source = f.source()
        var calls = 0
        assertThrows(IllegalStateException::class.java) {
            KnowledgePrimaryReclaim.advance(f.db, f.parts) { if (++calls == 12) error("fixture cancellation") }
        }
        f.verify(); assertEquals(source, f.source(48))
        assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_primary_compaction WHERE source<>''"))
        assertEquals(16, f.drain()); f.verify()
    }

    @Test fun catalogFailureCannotPublishOrRetireAnyMovedRecord() = KnowledgePrimaryCompactionFixture().use { f ->
        f.seed(); val source = f.source()
        f.db.execSQL("CREATE TRIGGER fail_move BEFORE UPDATE ON knowledge_primary_refs BEGIN SELECT RAISE(ABORT,'fixture failure'); END")
        assertThrows(Exception::class.java) { KnowledgePrimaryReclaim.advance(f.db, f.parts) { } }
        f.db.execSQL("DROP TRIGGER fail_move")
        f.verify(); assertEquals(source, f.source(48))
        assertTrue(File(f.root, "$source.sqlite").isFile)
        assertEquals(16, f.drain())
    }

    @Test fun corruptedFrameFailsClosedWithoutRetiringSource() = KnowledgePrimaryCompactionFixture().use { f ->
        f.seed(); val source = f.source()
        val path = File(f.root, "$source.sqlite")
        KnowledgeSqlite(path.absolutePath).use { it.execSQL("UPDATE frames SET ciphertext='corrupted'") }
        assertThrows(Exception::class.java) { KnowledgePrimaryReclaim.advance(f.db, f.parts) { } }
        assertTrue(path.isFile)
        assertEquals(source, f.source(48))
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_primary_retired"))
    }

    @Test fun lastLiveRecordsDeletedBetweenPagesAreRetiredSafely() = KnowledgePrimaryCompactionFixture().use { f ->
        f.seed()
        assertEquals(8, KnowledgePrimaryReclaim.advance(f.db, f.parts) { }.movedRecords)
        f.transaction { for (i in 56..63) f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(i))) }
        assertEquals(0, f.drain())
        for (i in 48..55) assertEquals("\u8bb0\u5fc6-$i", f.parts.read(f.db, f.key(i)))
        assertEquals(8L, f.number("SELECT count(*) FROM knowledge_primary_refs"))
    }

    @Test fun repeatedUpdatesRequeuePreviouslyHealthyPartitions() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { repeat(20) { f.put(it) } }
        assertEquals(0, f.drain())
        f.transaction { repeat(5) { f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(it))) } }
        assertEquals(0, f.drain())
        f.transaction { for (i in 5..9) f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(i))) }
        assertEquals(10, f.drain())
        for (i in 10..19) assertEquals("\u8bb0\u5fc6-$i", f.parts.read(f.db, f.key(i)))
    }

    @Test fun streamingRelocationPreservesLargeUnicodeBodyAndEncryption() = KnowledgePrimaryCompactionFixture().use { f ->
        val body = "\u4e2d\u6587\ud83d\ude80".repeat(40_000)
        f.transaction { f.put(1, "obsolete"); f.put(1, body) }
        val source = f.source(1)
        assertEquals(1, f.drain())
        assertEquals(body, f.parts.read(f.db, f.key(1)))
        assertFalse(File(f.root, "$source.sqlite").exists())
        f.root.listFiles()!!.filter { it.extension == "sqlite" }.forEach {
            assertFalse(it.readBytes().toString(Charsets.UTF_8).contains("\u4e2d\u6587\ud83d\ude80"))
        }
    }

    @Test fun upgradeDiscoversExistingShardsInBoundedPages() = KnowledgePrimaryCompactionFixture(records = 1, schema = false).use { f ->
        f.transaction { repeat(40) { f.put(it) } }
        KnowledgePrimaryCompactionSchema.create(f.db)
        val first = KnowledgePrimaryReclaim.advance(f.db, f.parts) { }
        assertFalse(first.complete)
        assertEquals(0L, f.number("SELECT discovered FROM knowledge_primary_compaction"))
        assertEquals(24L, f.number("SELECT count(*) FROM knowledge_primary_dirty"))
        assertEquals(0, f.drain())
        f.transaction { repeat(40) { f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(it))) } }
        f.drain()
        assertEquals(0, f.root.listFiles()!!.count { it.extension == "sqlite" })
    }

    @Test fun publishedRetirementSurvivesReopenBeforeUnlink() {
        var source = ""
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.transaction { f.put(1, "old"); f.put(1, "new") }; source = f.source(1)
            f.transaction { assertEquals(1, KnowledgePrimaryCompaction.advance(f.db, f.parts) { }) }
            assertTrue(File(f.root, "$source.sqlite").exists())
            assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_retired"))
            f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            f.drain(); assertFalse(File(f.root, "$source.sqlite").exists())
            assertEquals("new", f.parts.read(f.db, f.key(1)))
        }
    }

    @Test fun ownerSnapshotDefersCompactionAndLogicalRevisionsStayUnchanged() = KnowledgeSourceReplaceFixture().use { f ->
        val items = (1..40).map { f.item(it) }
        f.store.replaceSource(items.first().source, items)
        f.store.replaceSource(items.first().source, items.map { it.copy(content = "\u65b0\u6b63\u6587 ${it.id}") })
        val expected = f.items()
        val selection = KnowledgeSourceSelection(f.db, AgentKnowledgeSourceReference(items.first().source))
        val revision = f.db.readCommitted(selection::revision)
        f.db.backupSnapshot().use { read ->
            assertNull(f.db.reclaimPrimary())
            assertEquals(expected.toSet(), read.items().toSet())
        }
        var pages = 0; var moved = 0
        do {
            val page = requireNotNull(f.db.reclaimPrimary())
            moved += page.movedRecords; assertTrue(++pages < 100)
        } while (!page.complete)
        assertEquals(40, moved)
        f.reopen()
        assertEquals(expected, f.items())
        assertEquals(revision, f.db.readCommitted { KnowledgeSourceSelection(f.db, AgentKnowledgeSourceReference(items.first().source)).revision(it) })
    }
}
