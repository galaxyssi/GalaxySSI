package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryStoreDeviceTest {
    @Test fun migrationPreservesCompletedVectorDocumentsAndTheirSourceBinding() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        KnowledgePrimaryLegacyFixture.rewrite(f.db, f.context, f.name, f.db.key("id", item.id), inline = true)
        val spec = KnowledgeVectorSpec("a".repeat(64), 4, 128)
        val encoder = object : KnowledgeVectorEncoder {
            override val spec = spec
            override fun tokenCount(text: String) = text.length
            override fun embed(text: String) = floatArrayOf(1f, 0f, 0f, 0f)
            override fun close() = Unit
        }
        encoder.use {
            val indexer = KnowledgeVectorIndexer(f.db.vectors(spec), encoder)
            var batches = 0
            while (indexer.runBatch(8).pending) check(++batches < 20)
        }
        val before = requireNotNull(f.db.vectors(spec).page(item.id)).use { it.total }
        assertTrue(before > 0)
        assertTrue(f.db.migratePrimaryPage().complete)
        f.reopen()
        requireNotNull(f.db.vectors(spec).page(item.id)).use { assertEquals(before, it.total) }
        assertEquals(listOf(item), f.store.list(8))
    }

    @Test fun snapshotDefersWholePartitionRetirementAndSurvivesOwnerReopen() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        f.db.backupSnapshot().use { read ->
            f.db.transaction { it.delete("knowledge_items", null, null) }
            assertNull(f.db.reclaimPrimary())
            assertEquals(listOf(item), read.items().toList())
        }
        f.reopen()
        val reclaimed = requireNotNull(f.db.reclaimPrimary())
        assertEquals(1, reclaimed.partitions); assertTrue(reclaimed.bytes > 0)
        assertTrue(reclaimed.complete)
        assertTrue(f.store.list(8).isEmpty())
    }

    @Test fun livePartitionCannotBeReclaimed() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        assertEquals(0L, requireNotNull(f.db.reclaimPrimary()).bytes)
        f.reopen()
        assertEquals(listOf(item), f.store.list(8))
    }

    @Test fun actualStoreUsesPhysicalPrimaryPartitionsForSmallAndLargeBodies() = KnowledgeSourceReplaceFixture().use { f ->
        val small = f.item(1).copy(content = "small quartzplanet")
        val large = f.item(2).copy(content = "\u5927\u578b\u6b63\u6587\ud83d\ude80".repeat(10000))
        f.store.upsert(small); f.store.upsert(large)
        f.db.readCommitted { db ->
            for ((table, count) in listOf("knowledge_primary_refs" to 2L, "knowledge_chunks" to 0L, "knowledge_payloads" to 0L)) {
                db.rawQuery("SELECT count(*) FROM $table", null).use { check(it.moveToFirst()); assertEquals(count, it.getLong(0)) }
            }
        }
        f.reopen()
        assertEquals(setOf(small, large), f.store.findByIds(setOf(small.id, large.id)).toSet())
        assertEquals(listOf(small), f.store.search("quartzplanet", 8))
    }

    @Test fun sourceReplacementRemainsAtomicWhenReferencePublicationFails() = KnowledgeSourceReplaceFixture().use { f ->
        val before = (1..12).map { f.item(it) }
        f.store.replaceSource(before.first().source, before)
        f.db.transaction { it.execSQL("CREATE TRIGGER reject_primary BEFORE INSERT ON knowledge_primary_refs " +
            "WHEN (SELECT count(*) FROM knowledge_primary_refs)>3 BEGIN SELECT RAISE(ABORT,'fixture publication failed'); END") }
        assertThrows(Exception::class.java) { f.store.replaceSource(before.first().source, (20..32).map { f.item(it) }) }
        f.db.transaction { it.execSQL("DROP TRIGGER reject_primary") }
        f.reopen()
        assertEquals(before.toSet(), f.store.list(100).toSet())
    }

    @Test fun backupAndSearchSnapshotsKeepOldBodiesButFinalValidationRejectsStaleResults() = KnowledgeSourceReplaceFixture().use { f ->
        val old = f.item(1).copy(content = "quartzplanet original")
        f.store.upsert(old)
        f.db.backupSnapshot().use { backup -> f.db.searchSnapshot().use { search ->
            val hits = KnowledgeLexicalSearch.search(search, "quartzplanet", 8)
            f.store.upsert(old.copy(content = "updated"))
            assertEquals(listOf(old), backup.items().toList())
            assertEquals(listOf(old), search.recent(8).toList())
            assertTrue(search.validate(hits).isEmpty())
        } }
        f.reopen()
        assertEquals("updated", f.store.findByIds(setOf(old.id)).single().content)
    }

    @Test fun oldInlineAndSegmentBodiesMigrateAcrossReopeningWithoutLogicalChanges() = KnowledgeSourceReplaceFixture().use { f ->
        val expected = (1..19).map { f.item(it).copy(content = "old corpus \u6b63\u6587 $it") }
        expected.forEach { item ->
            f.store.upsert(item)
            KnowledgePrimaryLegacyFixture.rewrite(f.db, f.context, f.name, f.db.key("id", item.id), inline = item.chunkIndex % 2 == 0)
        }
        val selection = KnowledgeSourceSelection(f.db, AgentKnowledgeSourceReference(expected.first().source))
        val revision = f.db.readCommitted(selection::revision)
        val first = f.db.migratePrimaryPage()
        assertEquals(8, first.moved); assertFalse(first.complete)
        f.reopen()
        while (!f.db.migratePrimaryPage().complete) { }
        assertEquals(expected.toSet(), f.store.list(100).toSet())
        assertEquals(revision, f.db.readCommitted(selection::revision))
        f.db.readCommitted { db ->
            for (table in listOf("knowledge_chunks", "knowledge_payloads")) {
                db.rawQuery("SELECT count(*) FROM $table", null).use { check(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
            }
        }
    }

    @Test fun failedMigrationRollsBackMovedPrefixAndCheckpoint() = KnowledgeSourceReplaceFixture().use { f ->
        val items = (1..10).map { f.item(it) }
        items.forEach {
            f.store.upsert(it)
            KnowledgePrimaryLegacyFixture.rewrite(f.db, f.context, f.name, f.db.key("id", it.id), inline = true)
        }
        var checks = 0
        assertThrows(IllegalStateException::class.java) { f.db.migratePrimaryPage { if (++checks == 3) error("fixture interruption") } }
        f.reopen()
        f.db.readCommitted { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_primary_refs", null).use { check(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
            db.rawQuery("SELECT after_item FROM knowledge_primary_migration", null).use { check(it.moveToFirst()); assertEquals("", it.getString(0)) }
        }
        assertEquals(items.toSet(), f.store.list(100).toSet())
        while (!f.db.migratePrimaryPage().complete) { }
        assertEquals(items.toSet(), f.store.list(100).toSet())
    }
}
