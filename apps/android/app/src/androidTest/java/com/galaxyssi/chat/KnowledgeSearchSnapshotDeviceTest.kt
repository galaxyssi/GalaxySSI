package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSearchSnapshotDeviceTest {
    @Test fun pendingKeysetPagesDoNotBlockWritersOrMixRevisions() = KnowledgePayloadTestFixture().use { f ->
        val original = (1..81).map { f.item(it, "quartzneedle knowledge $it") }
        original.forEach(f.store::upsert)
        f.db.transaction { sql ->
            sql.execSQL("DELETE FROM knowledge_fts")
            sql.execSQL("DELETE FROM knowledge_fts_rows")
            sql.execSQL("INSERT INTO knowledge_fts_pending SELECT item_key FROM knowledge_items")
            sql.execSQL("CREATE TRIGGER test_no_fts BEFORE INSERT ON knowledge_fts_rows " +
                "BEGIN SELECT RAISE(ABORT,'paused test indexing'); END")
        }
        f.db.searchSnapshot().use { read ->
            val iterator = read.candidates("quartzneedle", 256).iterator()
            val first = (1..33).map { assertTrue(iterator.hasNext()); iterator.next() }
            writer {
                f.db.transaction { sql ->
                    sql.execSQL("DROP TRIGGER test_no_fts")
                    f.db.write(sql, original.last().copy(content = "cobalt replacement"))
                    sql.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", original.first().id)))
                    f.db.write(sql, f.item(100, "quartzneedle new record"))
                }
            }
            val all = first + iterator.asSequence().toList()
            assertEquals(original.toSet(), all.toSet())
            assertEquals(81, all.size)
            val ranked = KnowledgeLexicalSearch.search(read, "quartzneedle", 24)
            val validated = read.validate(ranked)
            assertFalse(validated.any { it.item.id == original.last().id || it.item.id == original.first().id })
        }
        assertEquals("payload-100", f.store.search("quartzneedle new record", 24).first().id)
    }

    @Test fun indexedSnapshotAndPublicationRespectConcurrentPermissionChanges() = KnowledgePayloadTestFixture().use { f ->
        val item = f.item(1, "quartzneedle private content").copy(cloudAccess = AgentKnowledgeCloudAccess.FULL)
        f.store.upsert(item)
        f.db.searchSnapshot().use { read ->
            val hits = KnowledgeLexicalSearch.search(read, "quartzneedle", 8)
            assertEquals(item, hits.single().item)
            writer { f.store.updateAccess(setOf(item.id), AgentKnowledgeCloudAccess.DENY,
                AgentKnowledgeAgentAccess.LOCAL_ONLY, emptyList()) }
            assertEquals(item, KnowledgeLexicalSearch.search(read, "quartzneedle", 8).single().item)
            assertTrue(read.validate(hits).isEmpty())
        }
        assertTrue(AgentKnowledgeRetriever.retrieve(f.store, "quartzneedle", "cloud-model:fixture").citations.isEmpty())
    }

    @Test fun searchPinsEncryptedFilesUntilItsReadViewCloses() = KnowledgePayloadTestFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        assertEquals(1L, f.count("knowledge_payloads"))
        f.db.searchSnapshot().use { read ->
            writer { f.db.transaction { it.delete("knowledge_items", null, null) } }
            assertNull(f.db.reclaimPayloads())
            assertEquals(item, read.recent(8).single())
            assertTrue(read.validate(listOf(AgentKnowledgeHit(item, 1.0, item.summary, emptyList()))).isEmpty())
        }
        assertNotNull(f.db.reclaimPayloads())
        assertTrue(f.store.list().isEmpty())
    }

    @Test fun queryOnlyViewClosesIdempotentlyAndReleasesLeaseOnFailure() = KnowledgePayloadTestFixture().use { f ->
        f.store.upsert(f.item(1, "quartzneedle"))
        val read = f.db.searchSnapshot()
        try { assertThrows(Exception::class.java) { read.access { it.execSQL("DELETE FROM knowledge_items") } } }
        finally { read.close(); read.close() }
        assertThrows(IllegalStateException::class.java) { read.recent(1).toList() }
        assertNotNull(f.db.reclaimPayloads())
        assertEquals(1L, f.store.stats().itemCount)
    }

    @Test fun pinnedPayloadReadDoesNotSerializeAnActualEncryptedAppend() = KnowledgePayloadTestFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        val row = KnowledgePayloadCompactionFixture.row(f, item.id)
        val reference = f.db.payloads.decodeReference(row.key, row.value)
        f.db.searchSnapshot().use { read ->
            val before = f.db.payloads.files.read(reference, f.db.payloads.aad(row.key)) { it.readBytes() }
            val after = f.db.payloads.files.readPinned(reference, f.db.payloads.aad(row.key)) { input ->
                val first = input.read()
                writer { f.store.upsert(f.item(2)) }
                byteArrayOf(first.toByte()) + input.readBytes()
            }
            assertArrayEquals(before, after)
            assertEquals(item, read.recent(8).single())
        }
        assertEquals(2, f.store.list().size)
    }

    @Test fun retirementInvalidatesOpenReadView() = KnowledgePayloadTestFixture().use { f ->
        f.store.upsert(f.item(1, "quartzneedle"))
        f.db.searchSnapshot().use { read ->
            f.store.close()
            assertThrows(IllegalStateException::class.java) { read.candidates("quartzneedle", 8).toList() }
            assertThrows(IllegalStateException::class.java) { read.validate(emptyList()) }
        }
        f.reopen()
        assertEquals(1, f.store.search("quartzneedle", 8).size)
    }

    @Test fun interruptionStopsBeforeDecryptingAndStillReleasesLease() = KnowledgePayloadTestFixture().use { f ->
        f.store.upsert(f.item(1, "quartzneedle"))
        writer {
            f.db.searchSnapshot().use { read ->
                val before = f.db.decryptedItemReads
                Thread.currentThread().interrupt()
                try {
                    assertThrows(IllegalStateException::class.java) { read.candidates("quartzneedle", 8).toList() }
                    assertEquals(before, f.db.decryptedItemReads)
                } finally { Thread.interrupted() }
            }
        }
        assertNotNull(f.db.reclaimPayloads())
    }

    @Test fun selectiveReadsAreBoundedAndNeverSilentlyIgnoreCorruptBodies() = KnowledgePayloadTestFixture().use { f ->
        (1..65).forEach { f.store.upsert(f.item(it, "ordinary material $it")) }
        f.store.upsert(f.item(100, "quartzneedle"))
        val before = f.db.decryptedItemReads
        assertEquals("payload-100", f.store.search("quartzneedle", 8).single().id)
        assertEquals(1L, f.db.decryptedItemReads - before)
        f.db.transaction { sql -> sql.execSQL("UPDATE knowledge_chunks SET ciphertext='invalid' WHERE item_key='" +
            f.db.key("id", "payload-100") + "'") }
        assertThrows(Exception::class.java) { f.store.search("quartzneedle", 8) }
        assertNotNull(f.db.reclaimPayloads())
    }

    private fun writer(action: () -> Unit) {
        val executor = Executors.newSingleThreadExecutor()
        try {
            val started = SystemClock.elapsedRealtime()
            executor.submit { action() }.get(10, TimeUnit.SECONDS)
            println("KNOWLEDGE_SEARCH_CONCURRENT_WRITER elapsed_ms=${SystemClock.elapsedRealtime() - started}")
        } finally {
            executor.shutdownNow()
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS))
        }
    }
}
