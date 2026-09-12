package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeReadAdmissionDeviceTest {
    @Test fun admissionReadsCommittedBodiesWhileWriterHasUncommittedChanges() = KnowledgeSourceReplaceFixture().use { f ->
        val original = f.item(1)
        f.store.upsert(original)
        heldWriter(f, { f.db.write(it, original.copy(content = "uncommitted replacement")) }) { awaitWriter ->
            awaitWriter()
            val started = System.nanoTime()
            f.db.searchSnapshot().use { assertEquals(original, it.recent(8).single()) }
            println("KNOWLEDGE_READ_ADMISSION phase=open_and_read elapsed_ns=${System.nanoTime() - started}")
        }
        assertEquals("uncommitted replacement", f.store.findByIds(setOf(original.id)).single().content)
    }

    @Test fun finalValidationDoesNotWaitForUnrelatedWriter() = KnowledgeSourceReplaceFixture().use { f ->
        val original = f.item(1)
        f.store.upsert(original)
        heldWriter(f, { f.db.write(it, f.item(2)) }) { awaitWriter ->
            f.db.searchSnapshot().use { read ->
                val hit = AgentKnowledgeHit(read.recent(8).single(), 1.0, original.summary, emptyList())
                awaitWriter()
                val started = System.nanoTime()
                assertEquals(listOf(hit), read.validate(listOf(hit)))
                println("KNOWLEDGE_READ_ADMISSION phase=validate elapsed_ns=${System.nanoTime() - started}")
            }
        }
        assertEquals(2L, f.store.stats().itemCount)
    }

    @Test fun failedColdMigrationCannotPublishReadyState() = KnowledgeSourceReplaceFixture().use { f ->
        val legacy = AgentEncryptedPreferences(f.context, "legacy-${f.name}")
        legacy.writeString("items", "not-json")
        assertThrows(Exception::class.java) { f.db.searchSnapshot() }
        assertThrows(Exception::class.java) { f.db.searchSnapshot() }
        assertEquals("not-json", legacy.readString("items", ""))
        legacy.writeString("items", "[]")
        f.db.searchSnapshot().use { assertTrue(it.recent(8).toList().isEmpty()) }
        f.store.upsert(f.item(1))
        f.db.searchSnapshot().use { assertEquals(f.item(1), it.recent(8).single()) }
    }

    @Test fun snapshotsInsideWriterAreRejectedAndRollbackPreservesCommittedView() = KnowledgeSourceReplaceFixture().use { f ->
        val original = f.item(1)
        f.store.upsert(original)
        assertThrows(IllegalStateException::class.java) { f.db.transaction { sql ->
            f.db.write(sql, original.copy(content = "rolled back"))
            f.db.searchSnapshot()
        } }
        f.db.searchSnapshot().use { assertEquals(original, it.recent(8).single()) }
    }

    @Test fun warmSearchRetriesFailedFtsMaintenanceWithoutWriterAdmission() = KnowledgeSourceReplaceFixture().use { f ->
        val original = f.item(1).copy(content = "retryneedle")
        f.store.upsert(original)
        val owner = f.db
        owner.transaction { sql ->
            sql.execSQL("DELETE FROM knowledge_fts")
            sql.execSQL("DELETE FROM knowledge_fts_rows")
            sql.execSQL("INSERT INTO knowledge_fts_pending SELECT item_key FROM knowledge_items")
            sql.execSQL("CREATE TRIGGER test_retry_fts BEFORE INSERT ON knowledge_fts_rows BEGIN SELECT RAISE(ABORT,'transient test failure'); END")
        }
        fun awaitCondition(condition: () -> Boolean) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (!condition() && System.nanoTime() < deadline) Thread.sleep(5)
            assertTrue(condition())
        }
        awaitCondition { owner.indexFailure != null }
        KnowledgeSqlite(f.context.getDatabasePath(f.name).absolutePath).use { sql ->
            // Do not enter owner.access: only the real warm query may trigger recovery.
            sql.execSQL("DROP TRIGGER test_retry_fts")
            assertEquals(original.id, f.store.search("retryneedle", 8).single().id)
            awaitCondition { sql.rawQuery("SELECT count(*) FROM knowledge_fts_pending", null).use {
                check(it.moveToFirst()); it.getLong(0) == 0L && owner.indexFailure == null
            } }
        }
    }

    private fun heldWriter(f: KnowledgeSourceReplaceFixture, mutate: (KnowledgeSqlite) -> Unit,
        read: (() -> Unit) -> Unit) {
        val readerReady = CountDownLatch(1)
        val writerReady = CountDownLatch(1)
        val release = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        val writer = pool.submit {
            check(readerReady.await(10, TimeUnit.SECONDS))
            f.db.transaction { sql ->
                mutate(sql); writerReady.countDown()
                check(release.await(10, TimeUnit.SECONDS))
            }
        }
        val reader = pool.submit { read { readerReady.countDown(); check(writerReady.await(10, TimeUnit.SECONDS)) } }
        try { reader.get(2, TimeUnit.SECONDS) } finally {
            release.countDown(); readerReady.countDown()
            try { writer.get(10, TimeUnit.SECONDS); runCatching { reader.get(10, TimeUnit.SECONDS) } }
            finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        }
    }
}
