package com.galaxyssi.chat

import android.system.Os
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryAllocationDeviceTest {
    private fun journal(f: KnowledgePrimaryCompactionFixture) = File(f.root.absolutePath + ".allocations.sqlite")
    private fun pending(f: KnowledgePrimaryCompactionFixture) = KnowledgeSqlite(journal(f).absolutePath).use { db ->
        db.rawQuery("SELECT count(*) FROM pending", null).use { check(it.moveToFirst()); it.getLong(0) }
    }
    private fun replay(f: KnowledgePrimaryCompactionFixture, remove: (String) -> Long = f.parts::removeRetired,
        checkActive: () -> Unit = {}) = f.parts.allocations.replay({ false }, { error("Unexpected reference") }, remove, checkActive)

    @Test fun committedPartitionIsKeptAndIntentIsForgotten() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; val id = f.source(1)
        assertEquals(1L, pending(f)); f.drain()
        assertEquals(0L, pending(f)); assertTrue(File(f.root, "$id.sqlite").isFile)
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }

    @Test fun rolledBackCatalogLeavesAnIntentAndReclaimsOnlyItsFile() = KnowledgePrimaryCompactionFixture().use { f ->
        var id = ""
        f.transaction(commit = false) { f.put(1); id = f.source(1) }
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
        assertTrue(File(f.root, "$id.sqlite").exists())
        val page = KnowledgePrimaryReclaim.advance(f.db, f.parts) { }
        assertEquals(1, page.orphanAllocations); assertTrue(page.bytes > 0); assertTrue(page.complete)
        assertFalse(File(f.root, "$id.sqlite").exists()); assertEquals(0L, pending(f))
    }

    @Test fun durableFramesWithoutCatalogPublicationAreReclaimedAfterReopen() {
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.transaction(commit = false) { f.put(1); f.parts.prepareCommit() }
            f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            val page = KnowledgePrimaryReclaim.advance(f.db, f.parts) { }
            assertEquals(1, page.orphanAllocations); assertTrue(page.bytes > 0)
            assertEquals(0L, pending(f)); assertTrue(f.root.listFiles()!!.isEmpty())
        }
    }

    @Test fun replayIsPagedAndAnIntentWithoutAFileIsIdempotent() = KnowledgePrimaryCompactionFixture().use { f ->
        repeat(37) { f.parts.allocations.remember(it.toString(16).padStart(32, '0')) }
        var pages = 0; var total = 0
        do { val page = replay(f); pages++; total += page.visited; assertTrue(page.visited <= 8); if (page.complete) break } while (pages < 10)
        assertEquals(5, pages); assertEquals(37, total)
        assertEquals(KnowledgePrimaryAllocations.Page(0, 0, 0, true), replay(f))
    }

    @Test fun interruptionAfterUnlinkRetainsAnIntentForIdempotentRetry() = KnowledgePrimaryCompactionFixture().use { f ->
        var id = ""; f.transaction(commit = false) { f.put(1); id = f.source(1) }
        assertThrows(IllegalStateException::class.java) { replay(f, remove = {
            f.parts.removeRetired(it); error("Interrupted after physical removal")
        }) }
        assertFalse(File(f.root, "$id.sqlite").exists()); assertEquals(1L, pending(f))
        assertTrue(replay(f).complete); assertEquals(0L, pending(f))
    }

    @Test fun cancellationBeforeReplayDoesNotModifyFilesOrIntents() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction(commit = false) { f.put(1) }
        assertThrows(IllegalStateException::class.java) { replay(f, checkActive = { error("Cancelled") }) }
        assertEquals(1L, pending(f)); assertEquals(1, f.root.listFiles()!!.size)
    }

    @Test fun unjournaledLegacyFilesAndUnrelatedNamesAreNotAdopted() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction(commit = false) { f.put(1) }
        val unknown = File(f.root, "a".repeat(32) + ".sqlite").apply { writeText("legacy") }
        val unrelated = File(f.root, "keep.txt").apply { writeText("unrelated") }
        f.drain(); assertEquals("legacy", unknown.readText()); assertEquals("unrelated", unrelated.readText())
    }

    @Test fun missingRegisteredFileIsNotSilentlyAcknowledged() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; val file = File(f.root, "${f.source(1)}.sqlite"); val held = File(f.root, "held")
        assertTrue(file.renameTo(held))
        try { assertThrows(IllegalStateException::class.java) { f.drain() }; assertEquals(1L, pending(f)) }
        finally { assertTrue(held.renameTo(file)) }
        f.drain(); assertEquals(0L, pending(f)); assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }

    @Test fun sidecarSymlinkRejectsTheWholeRemovalBeforeDeletingTheMainFile() = KnowledgePrimaryCompactionFixture().use { f ->
        var id = ""; f.transaction(commit = false) { f.put(1); id = f.source(1) }
        val file = File(f.root, "$id.sqlite")
        val external = File(f.root.parentFile, "${f.name}.preserved").apply { writeText("preserved") }
        val sidecar = File(file.absolutePath + "-wal"); Os.symlink(external.absolutePath, sidecar.absolutePath)
        try {
            assertThrows(IllegalStateException::class.java) { replay(f) }
            assertTrue(file.isFile); assertEquals("preserved", external.readText()); assertEquals(1L, pending(f))
        } finally { assertTrue(sidecar.delete()) }
        assertTrue(replay(f).complete)
    }

    @Test fun allocationJournalSymlinkCannotBeOpenedOrReplayed() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction(commit = false) { f.put(1) }
        val path = journal(f); val held = File(path.absolutePath + ".held")
        assertTrue(path.renameTo(held)); Os.symlink(held.absolutePath, path.absolutePath)
        try { assertThrows(IllegalStateException::class.java) { replay(f) }; assertThrows(IllegalStateException::class.java) { f.parts.allocations.remember("f".repeat(32)) } }
        finally { assertTrue(path.delete()); assertTrue(held.renameTo(path)) }
        assertTrue(replay(f).complete)
    }

    @Test fun malformedAllocationIdentifiersCannotEscapeTheirRoot() = KnowledgePrimaryCompactionFixture().use { f ->
        for (id in listOf("../other", "a".repeat(31), "A".repeat(32), "a".repeat(33))) {
            assertThrows(IllegalArgumentException::class.java) { f.parts.allocations.remember(id) }
        }
        assertFalse(journal(f).exists())
    }

    @Test fun liveSnapshotDefersOrphanReclamation() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(1))
        f.db.backupSnapshot().use { snapshot ->
            assertThrows(IllegalStateException::class.java) { f.db.transaction { db -> f.db.write(db, f.item(2)); error("Rollback") } }
            assertNull(f.db.reclaimPrimary())
            assertEquals(1, snapshot.items().count())
        }
        while (!requireNotNull(f.db.reclaimPrimary()).complete) { }
        assertEquals(1, f.items().size)
    }

    @Test fun failedIntentPersistenceCannotCreateAnUntrackedBodyFile() = KnowledgePrimaryCompactionFixture().use { f ->
        assertTrue(journal(f).mkdir())
        assertThrows(IllegalStateException::class.java) { f.transaction { f.put(1) } }
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_items"))
        assertEquals(0, f.root.listFiles()!!.size)
    }

    @Test fun profileOneHundredDurableNewPartitions() = KnowledgePrimaryCompactionFixture(records = 1).use { f ->
        val cold = System.nanoTime(); f.transaction { f.put(0) }; val coldNanos = System.nanoTime() - cold
        val times = (1..100).map { i ->
            val start = System.nanoTime(); f.transaction { f.put(i, "\u5206\u7247\u5199\u5165-$i") }; System.nanoTime() - start
        }.sorted()
        assertEquals(101L, pending(f)); assertEquals(101L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
        for (i in 1..100) assertEquals("\u5206\u7247\u5199\u5165-$i", f.parts.read(f.db, f.key(i)))
        f.drain(); assertEquals(0L, pending(f))
        println("KNOWLEDGE_PRIMARY_ALLOCATION_PROFILE samples=100 p50_ns=${times[49]} p95_ns=${times[94]} " +
            "max_ns=${times.last()} cold_ns=$coldNanos within_200ms=${times.count { it <= 200_000_000L }} journal_bytes=${journal(f).length()}")
    }
}
