package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceExportSnapshotDeviceTest {
    private fun export(f: KnowledgeBackupTestFixture) = f.store.sourceExport(AgentKnowledgeSourceReference("shared"))
    private fun seed(f: KnowledgeBackupTestFixture, count: Int) = f.db.transaction { db ->
        (1..count).forEach { f.db.write(db, f.item(it).copy(source = "shared", chunkIndex = count - it, chunkCount = count)) }
    }

    @Test fun snapshotUsesBoundedIndexedPagesAndLegacyAdapterPreservesChunkOrder() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 129)
        val projection = export(f); val initialReads = f.db.decryptedItemReads
        projection.snapshot().use { snapshot ->
            assertEquals(0L, snapshot.loadedKeys)
            val iterator = snapshot.items().iterator()
            assertTrue(iterator.hasNext()); assertEquals(64L, snapshot.loadedKeys)
            assertEquals(initialReads + 1, f.db.decryptedItemReads)
            assertEquals("backup-129", iterator.next().id)
            val rest = iterator.asSequence().map { it.id }.toList()
            assertEquals((128 downTo 1).map { "backup-$it" }, rest)
            assertEquals(64, snapshot.largestKeyPage); assertEquals(129L, snapshot.loadedKeys)
            assertEquals(129, snapshot.items().count())
        }
        assertEquals((129 downTo 1).map { "backup-$it" }, projection.items().map { it.id })
        f.db.access { db -> db.rawQuery("EXPLAIN QUERY PLAN ${KnowledgeSourceSnapshot.PAGE_SQL}",
            arrayOf("s:${f.db.key("source", "shared")}", Long.MIN_VALUE.toString(), "")).use { c ->
            val details = buildList { while (c.moveToNext()) add(c.getString(3)) }.joinToString(" ")
            assertTrue(details, details.contains("knowledge_source_members_order"))
            assertTrue(details, details.contains("SEARCH")); assertFalse(details, details.contains("TEMP B-TREE"))
        } }
    }

    @Test fun writerCommitsWhileReaderKeepsOriginalSourceAndNextSnapshotRejectsStaleToken() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 65); val projection = export(f)
        val executor = Executors.newSingleThreadExecutor()
        try {
            projection.snapshot().use { snapshot ->
                val iterator = snapshot.items().iterator()
                val original = iterator.next()
                executor.submit { f.db.transaction { db ->
                    f.db.write(db, f.item(1, "\u65b0\u7248\u5185\u5bb9").copy(source = "shared"))
                    db.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", "backup-2")))
                    f.db.write(db, f.item(66).copy(source = "shared"))
                } }.get(5, TimeUnit.SECONDS)
                val rest = iterator.asSequence().toList()
                assertEquals(65, rest.size + 1); assertEquals("backup-65", original.id)
                assertEquals(f.item(1).content, rest.single { it.id == "backup-1" }.content)
                assertTrue(rest.any { it.id == "backup-2" }); assertFalse(rest.any { it.id == "backup-66" })
            }
            assertThrows(IllegalStateException::class.java) { projection.snapshot().close() }
            assertEquals(65, export(f).snapshot().use { it.items().count() })
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun partialConsumptionCloseAndOwnerRetirementInvalidateLazyIterators() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 65)
        val snapshot = export(f).snapshot(); val iterator = snapshot.items().iterator()
        iterator.next(); snapshot.close(); snapshot.close()
        assertThrows(IllegalStateException::class.java) { iterator.next() }
        val next = export(f).snapshot()
        f.store.close()
        try { assertThrows(IllegalStateException::class.java) { next.items().first() } } finally { next.close() }
        f.reopen(); assertEquals(65, export(f).items().size)
    }

    @Test fun missingSourceIsEmptyAndLocalNotesAreIsolated() = KnowledgeBackupTestFixture().use { f ->
        assertTrue(export(f).snapshot().use { it.items().none() })
        f.store.upsert(f.item(1).copy(source = "")); f.store.upsert(f.item(2).copy(source = ""))
        val note = f.store.sourceExport(AgentKnowledgeSourceReference("", "backup-1"))
        assertEquals(listOf("backup-1"), note.snapshot().use { it.items().map { row -> row.id }.toList() })
    }

    @Test fun mutatedHeaderOrBodyIsNotTrustedBecauseARevisionTokenExists() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 1)
        f.db.access { it.execSQL("UPDATE knowledge_chunks SET ciphertext='corrupt'") }
        assertThrows(Exception::class.java) { export(f).snapshot().use { it.items().toList() } }
        seed(f, 1)
        f.db.access { it.execSQL("UPDATE knowledge_items SET header='corrupt'") }
        assertThrows(Exception::class.java) { export(f).snapshot().use { it.items().toList() } }
        Unit
    }

    @Test fun timestampExtremesAndTiesTraverseOnceWithoutSkippingOrDuplicating() = KnowledgeBackupTestFixture().use { f ->
        f.db.transaction { db -> (1..130).forEach { i ->
            val updated = when (i) { 1 -> Long.MIN_VALUE; 2 -> Long.MAX_VALUE; else -> 0L }
            f.db.write(db, f.item(i).copy(source = "shared", updatedAtMillis = updated))
        } }
        val rows = export(f).snapshot().use { it.items().toList() }
        assertEquals(130, rows.size); assertEquals(130, rows.map { it.id }.toSet().size)
        assertEquals("backup-2", rows.first().id); assertEquals("backup-1", rows.last().id)
    }

    @Test fun missingDirectoryIsAnErrorNotAnEmptyExport() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 2)
        f.db.access { it.execSQL("DELETE FROM knowledge_source_directory") }
        assertThrows(IllegalStateException::class.java) { export(f).snapshot().close() }
        Unit
    }

    @Test fun uncommittedRevisionCannotOpenACommittedSnapshotAndFailureClosesItsConnection() = KnowledgeBackupTestFixture().use { f ->
        seed(f, 2)
        val before = export(f)
        assertThrows(IllegalStateException::class.java) { f.db.transaction { db ->
            f.db.write(db, f.item(3).copy(source = "shared"))
            export(f).snapshot().close()
        } }
        assertEquals(before.revision, export(f).revision)
        assertEquals(2, before.snapshot().use { it.items().count() })
        f.store.upsert(f.item(4).copy(source = "shared"))
        assertEquals(3, export(f).snapshot().use { it.items().count() })
    }
}
