package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryCopyDeviceTest {
    private val body get() = "\u4e2d\u6587\ud83d\ude80".repeat(KnowledgePrimaryFrameCodec.CHARS * 10) + "\u5b8c"
    private fun seed(f: KnowledgePrimaryCompactionFixture) {
        f.transaction { f.put(1, "obsolete"); f.put(1, body) }
        assertEquals(0, KnowledgePrimaryReclaim.advance(f.db, f.parts) { }.movedRecords)
        assertEquals(0, state(f).copied)
    }
    private fun job(f: KnowledgePrimaryCompactionFixture) = requireNotNull(KnowledgePrimaryCopy(f.parts).load(f.db))
    private fun state(f: KnowledgePrimaryCompactionFixture) = KnowledgePrimaryCopy(f.parts).state(job(f))
    private fun advance(f: KnowledgePrimaryCompactionFixture) = KnowledgePrimaryReclaim.advance(f.db, f.parts) { }

    @Test fun boundedCopyAndVerificationResumeBetweenReopens() {
        val name = KnowledgePrimaryCompactionFixture().use { f -> seed(f); f.name }
        var moved = 0
        var pages = 0
        do {
            val complete = KnowledgePrimaryCompactionFixture(name).use { f ->
                val old = if (KnowledgePrimaryCopy.pending(f.db)) state(f) else null
                val page = advance(f)
                moved += page.movedRecords
                assertEquals(body, f.parts.read(f.db, f.key(1)))
                if (KnowledgePrimaryCopy.pending(f.db)) {
                    val now = state(f)
                    assertTrue(now.copied - requireNotNull(old).copied in 0..16)
                    assertTrue(now.verified - old.verified in 0..16)
                    assertEquals(job(f).source, f.source(1))
                    assertEquals(1L, f.number("SELECT sealed FROM knowledge_primary_partitions WHERE partition_key='${job(f).destination}'"))
                }
                page.complete
            }
            assertTrue(++pages < 20)
        } while (!complete)
        assertEquals(1, moved)
        assertTrue(pages >= 6)
    }

    @Test fun cooperativeYieldCommitsOnlyCompletedFramePrefix() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        var checks = 0
        f.transaction {
            f.parts.resumeCopy(f.db) { if (++checks >= 4) throw MemoryMaintenanceYield() }
        }
        assertEquals(2, state(f).copied)
        assertEquals(1, f.drain())
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun hardCancellationRollsBackCopyCheckpoint() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        var checks = 0
        assertThrows(IllegalStateException::class.java) {
            f.transaction { f.parts.resumeCopy(f.db) { if (++checks == 4) error("cancel copy") } }
        }
        assertEquals(0, state(f).copied)
        assertEquals(1, f.drain())
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun physicalCommitBeforeCatalogRollbackReplaysUnpublishedTail() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        f.transaction(commit = false) { f.parts.resumeCopy(f.db) { }; f.parts.prepareCommit() }
        assertEquals(0, state(f).copied)
        KnowledgeSqlite(File(f.root, "${job(f).destination}.sqlite").absolutePath).use { db ->
            db.rawQuery("SELECT count(*) FROM frames", null).use { assertTrue(it.moveToFirst()); assertEquals(16, it.getInt(0)) }
        }
        advance(f)
        assertEquals(16, state(f).copied)
        assertEquals(1, f.drain())
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun replacementWinsWhileCopyIsInProgress() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f); advance(f)
        val destination = job(f).destination
        f.transaction { f.put(1, "\u7528\u6237\u65b0\u5185\u5bb9") }
        f.drain()
        assertEquals("\u7528\u6237\u65b0\u5185\u5bb9", f.parts.read(f.db, f.key(1)))
        assertFalse(File(f.root, "$destination.sqlite").exists())
    }

    @Test fun deletionWinsWhileCopyIsInProgress() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f); advance(f)
        f.transaction { f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(1))) }
        f.drain()
        assertNull(f.parts.read(f.db, f.key(1)))
        assertFalse(KnowledgePrimaryCopy.pending(f.db))
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
    }

    @Test fun corruptCheckpointFailsClosedAndLeavesSourceReadable() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        val original = job(f)
        f.db.execSQL("UPDATE knowledge_primary_copy SET checkpoint='corrupt'")
        assertThrows(Exception::class.java) { advance(f) }
        assertEquals(original.source, f.source(1))
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun checkpointCannotBeReboundToAnotherOriginal(): Unit = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        val original = job(f)
        assertThrows(Exception::class.java) { f.parts.openCopy(original.copy(key = f.key(2))) }
        assertThrows(Exception::class.java) { f.parts.openCopy(original.copy(original = original.original + "x")) }
        assertThrows(Exception::class.java) { f.parts.openCopy(original.copy(destination = original.source)) }
    }

    @Test fun corruptedDestinationIsRejectedBeforePublication() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        while (state(f).copied < 41) advance(f)
        val original = job(f)
        KnowledgeSqlite(File(f.root, "${original.destination}.sqlite").absolutePath).use {
            it.execSQL("UPDATE frames SET ciphertext='corrupted' WHERE ordinal=0")
        }
        assertThrows(Exception::class.java) { advance(f) }
        assertEquals(original.source, f.source(1))
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun authenticatedButAlteredFrameFailsDigestVerification() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        while (state(f).copied < 41) advance(f)
        val original = job(f)
        val cursor = state(f)
        val target = KnowledgePrimaryPartitions.Reference(original.destination, cursor.entry, 41, body.length)
        f.transaction {
            f.parts.trimCopy(target, 40)
            f.parts.writeCopyFrame(f.key(1), target, 40, KnowledgePrimaryFrameCodec.compress("x"))
        }
        assertThrows(IllegalStateException::class.java) { f.drain() }
        assertEquals(original.source, f.source(1))
        assertEquals(body, f.parts.read(f.db, f.key(1)))
    }

    @Test fun ignoredPublicationMustNotClaimSuccess() = KnowledgePrimaryCompactionFixture().use { f ->
        seed(f)
        val source = f.source(1)
        f.db.execSQL("CREATE TRIGGER ignore_move BEFORE UPDATE ON knowledge_primary_refs BEGIN SELECT RAISE(IGNORE); END")
        assertThrows(IllegalStateException::class.java) { f.drain() }
        assertEquals(source, f.source(1))
        assertTrue(KnowledgePrimaryCopy.pending(f.db))
        f.db.execSQL("DROP TRIGGER ignore_move")
        assertEquals(1, f.drain())
    }

    @Test fun smallRecordYieldKeepsAlreadyMovedPrefix() = KnowledgePrimaryCompactionFixture().use { f ->
        f.seed()
        var moved = 0
        f.transaction {
            moved = KnowledgePrimaryCompaction.advance(f.db, f.parts) {
                if (f.number("SELECT count(*) FROM knowledge_primary_refs WHERE partition_key<>(SELECT source FROM knowledge_primary_compaction)") in 1..15) {
                    throw MemoryMaintenanceYield()
                }
            }
        }
        assertEquals(1, moved)
        assertEquals(15, f.drain())
        f.verify()
    }
}
