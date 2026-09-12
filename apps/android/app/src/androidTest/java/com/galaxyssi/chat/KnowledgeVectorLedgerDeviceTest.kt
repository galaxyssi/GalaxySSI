package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeVectorLedgerDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("a".repeat(64), 4, 32)
    private fun item(id: String = "first", text: String = "\u79c1\u5bc6\u8bb0\u5fc6".repeat(40)) =
        AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, text, source = "source")
    private class FixtureEncoder(override val spec: KnowledgeVectorSpec) : KnowledgeVectorEncoder {
        var before: () -> Unit = {}
        var last: FloatArray? = null
        override fun tokenCount(text: String) = text.codePointCount(0, text.length) + 2
        override fun embed(text: String): FloatArray {
            before()
            return FloatArray(spec.dimensions) { if (it == 0) 1f else 0f }.also { last = it }
        }
        override fun close() = Unit
    }
    private class Fixture(val store: SQLiteAgentKnowledgeStore, val db: AgentKnowledgeDatabase, val name: String, val legacy: String)
    private fun isolated(block: (Fixture) -> Unit) {
        val name = "test-vectors-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        try {
            block(Fixture(SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> },
                AgentKnowledgeDatabase.shared(context, name, legacy), name, legacy))
        } finally {
            AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
    }
    private fun finish(ledger: KnowledgeVectorLedger, encoder: KnowledgeVectorEncoder) {
        repeat(2000) { if (!KnowledgeVectorIndexer(ledger, encoder).runBatch().pending) return }
        fail("Vector fixture did not finish")
    }

    @Test fun checkpointsSurviveReopenAndIncompleteVectorsAreNeverVisible() = isolated { f ->
        f.store.upsert(item())
        val ledger = f.db.vectors(spec)
        val encoder = FixtureEncoder(spec)
        assertEquals(1, f.store.indexVectorChunks(encoder, 1).committedChunks)
        assertTrue(requireNotNull(encoder.last).all { it == 0f })
        assertNull(ledger.page("first"))
        assertEquals(1, requireNotNull(ledger.nextJob()).count)
        AgentKnowledgeDatabase.release(context, f.name)
        val reopened = AgentKnowledgeDatabase.shared(context, f.name, f.legacy)
        val resumed = reopened.vectors(spec)
        assertEquals(1, requireNotNull(resumed.nextJob()).count)
        finish(resumed, encoder)
        val before = reopened.decryptedItemReads
        val first = requireNotNull(resumed.page("first", limit = 1))
        val total = first.total
        assertTrue(total > 1)
        val values = first.rows.single().values
        assertEquals(1f, values[0]); first.close(); assertTrue(values.all { it == 0f })
        for (ordinal in 1 until total) requireNotNull(resumed.page("first", ordinal, 1)).use {
            assertEquals(ordinal, it.rows.single().ordinal)
        }
        assertEquals("Vector pages must not decrypt source bodies", before, reopened.decryptedItemReads)
    }

    @Test fun sourceEditAndDeleteRejectAlreadyRunningOldWork() = isolated { f ->
        f.store.upsert(item())
        val ledger = f.db.vectors(spec)
        val job = requireNotNull(ledger.nextJob())
        val encoder = FixtureEncoder(spec)
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(job.item.content, job.next, 32, encoder::tokenCount))
        f.store.upsert(item(text = "replacement"))
        assertFalse(ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)))
        finish(ledger, encoder)
        assertNotNull(ledger.page("first")?.also { it.close() })
        f.store.replaceAllJson(org.json.JSONArray())
        assertFalse(ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)))
        assertNull(ledger.page("first"))
        f.db.access { sql -> sql.rawQuery("SELECT count(*) FROM knowledge_vectors", null).use {
            assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
        } }
        f.store.upsert(item("later", "new knowledge after deletion"))
        assertEquals("later", requireNotNull(ledger.nextJob()).item.id)
    }

    @Test fun repeatedCommitIsIdempotentAndFailureRollsBackChunkAndCheckpoint() = isolated { f ->
        f.store.upsert(item())
        val ledger = f.db.vectors(spec)
        val job = requireNotNull(ledger.nextJob())
        val encoder = FixtureEncoder(spec)
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(job.item.content, 0, 32, encoder::tokenCount))
        f.db.access { it.execSQL("CREATE TRIGGER reject_vector_marker BEFORE UPDATE ON knowledge_vector_docs " +
            "BEGIN SELECT RAISE(ABORT,'fixture checkpoint failure'); END") }
        assertThrows(Exception::class.java) { ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)) }
        assertEquals(0, requireNotNull(ledger.nextJob()).count)
        f.db.access { it.execSQL("DROP TRIGGER reject_vector_marker") }
        assertTrue(ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)))
        assertFalse(ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)))
        assertEquals(1, requireNotNull(ledger.nextJob()).count)
    }

    @Test fun cancelledOrStaleModelResultIsWipedWithoutCommitting() = isolated { f ->
        f.store.upsert(item())
        val encoder = FixtureEncoder(spec)
        var cancelled = false
        encoder.before = { cancelled = true }
        assertEquals(0, f.store.indexVectorChunks(encoder, 1) { cancelled }.committedChunks)
        assertTrue(requireNotNull(encoder.last).all { it == 0f })
        assertEquals(0, requireNotNull(f.db.vectors(spec).nextJob()).count)
        encoder.before = { f.store.upsert(item(text = "new source while inference is outside the DB lock")) }
        val result = f.store.indexVectorChunks(encoder, 1)
        assertEquals(1, result.staleResults)
        assertTrue(requireNotNull(encoder.last).all { it == 0f })
    }

    @Test fun concurrentWritersCommitOnlyOneCopyOfTheSameChunk() = isolated { f ->
        f.store.upsert(item())
        val ledger = f.db.vectors(spec)
        val job = requireNotNull(ledger.nextJob())
        val encoder = FixtureEncoder(spec)
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(job.item.content, 0, 32, encoder::tokenCount))
        val executor = java.util.concurrent.Executors.newFixedThreadPool(2)
        try {
            val gate = java.util.concurrent.CountDownLatch(1)
            val results = (1..2).map { executor.submit(java.util.concurrent.Callable {
                gate.await()
                ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f))
            }) }
            gate.countDown()
            assertEquals(1, results.count { it.get(20, java.util.concurrent.TimeUnit.SECONDS) })
            assertEquals(1, requireNotNull(ledger.nextJob()).count)
        } finally { executor.shutdownNow() }
    }

    @Test fun modelRevisionsAndDimensionsNeverShareStoredVectors() = isolated { f ->
        f.store.upsert(item(text = "short"))
        val first = f.db.vectors(spec)
        finish(first, FixtureEncoder(spec))
        val otherSpec = spec.copy(modelSha256 = "b".repeat(64), dimensions = 8)
        val other = f.db.vectors(otherSpec)
        assertNull(other.page("first"))
        finish(other, FixtureEncoder(otherSpec))
        requireNotNull(first.page("first")).use { assertEquals(4, it.rows.single().values.size) }
        requireNotNull(other.page("first")).use { assertEquals(8, it.rows.single().values.size) }
        first.unregister()
        assertNull(first.page("first"))
        requireNotNull(other.page("first")).use { assertEquals(8, it.rows.single().values.size) }
        assertEquals(1L, f.store.stats().itemCount)
    }

    @Test fun checkpointTamperingAndMissingChunksFailInsteadOfReturningPartialResults() = isolated { f ->
        f.store.upsert(item())
        val ledger = f.db.vectors(spec)
        finish(ledger, FixtureEncoder(spec))
        f.db.access { it.execSQL("DELETE FROM knowledge_vectors WHERE ordinal=1") }
        assertThrows(IllegalStateException::class.java) { ledger.page("first") }
        f.db.access { it.execSQL("UPDATE knowledge_vector_docs SET next_offset=next_offset-1") }
        assertThrows(Exception::class.java) { ledger.page("first") }
    }

    @Test fun ciphertextCannotMoveBetweenDocumentsAndInvalidVectorsCannotAdvanceProgress() = isolated { f ->
        f.store.upsert(item("first", "one")); f.store.upsert(item("second", "two"))
        val ledger = f.db.vectors(spec)
        val job = requireNotNull(ledger.nextJob())
        val encoder = FixtureEncoder(spec)
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(job.item.content, 0, 32, encoder::tokenCount))
        for (bad in listOf(floatArrayOf(Float.NaN, 0f, 0f, 0f), FloatArray(4), FloatArray(3))) {
            assertThrows(IllegalArgumentException::class.java) { ledger.append(job, chunk, bad) }
        }
        finish(ledger, encoder)
        f.db.access { sql ->
            val copied = sql.rawQuery("SELECT ciphertext FROM knowledge_vectors WHERE item_key=?", arrayOf(f.db.key("id", "first"))).use {
                assertTrue(it.moveToFirst()); it.getBlob(0)
            }
            sql.update("knowledge_vectors", ContentValues().apply { put("ciphertext", copied) },
                "item_key=?", arrayOf(f.db.key("id", "second")))
        }
        assertThrows(Exception::class.java) { ledger.page("second") }
    }

    @Test fun sourceReplacementRollbackPreservesCompletedVectors() = isolated { f ->
        f.store.upsert(item(text = "original"))
        val ledger = f.db.vectors(spec)
        finish(ledger, FixtureEncoder(spec))
        f.db.access { it.execSQL("CREATE TRIGGER reject_replacement BEFORE INSERT ON knowledge_chunks " +
            "BEGIN SELECT RAISE(ABORT,'fixture source failure'); END") }
        assertThrows(Exception::class.java) { f.store.upsert(item(text = "replacement")) }
        requireNotNull(ledger.page("first")).use { assertEquals(1, it.total) }
    }

    @Test fun binaryCipherBindsAadAndKeepsTextCipherCompatible() {
        val plaintext = ByteArray(2048) { (it % 251).toByte() }
        val aad = "vector fixture".toByteArray()
        val encrypted = AgentStorageCipher.encryptBinary(plaintext, aad)
        assertFalse(encrypted.contentEquals(plaintext))
        val decoded = AgentStorageCipher.decryptBinary(encrypted, aad)
        try { assertArrayEquals(plaintext, decoded) } finally { decoded.fill(0) }
        assertThrows(Exception::class.java) { AgentStorageCipher.decryptBinary(encrypted, "wrong".toByteArray()) }
        encrypted[encrypted.lastIndex] = (encrypted.last().toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { AgentStorageCipher.decryptBinary(encrypted, aad) }
        val old = AgentStorageCipher.encrypt("existing text", aad)
        assertEquals("existing text", AgentStorageCipher.decrypt(old, aad))
        plaintext.fill(0)
    }

    @Test fun versionTwoUpgradeKeepsSourceAndCreatesPendingVectorState() = isolated { f ->
        f.store.upsert(item(text = "existing v2 knowledge"))
        f.db.sourceMaintenance.close()
        f.db.access {
            KnowledgeVectorChangeFixtureSchema.remove(it)
            it.execSQL("DROP TRIGGER knowledge_vector_source_insert")
            it.execSQL("DROP TABLE knowledge_vector_queue")
            it.execSQL("DROP TABLE knowledge_vectors")
            it.execSQL("DROP TABLE knowledge_vector_docs")
            it.execSQL("DROP TABLE knowledge_vector_models")
            for (operation in listOf("insert", "update", "delete")) it.execSQL("DROP TRIGGER knowledge_browse_$operation")
            it.execSQL("DROP INDEX IF EXISTS knowledge_source_recent")
            it.execSQL("DROP TABLE knowledge_browse_revision")
            it.execSQL("PRAGMA user_version=2")
        }
        AgentKnowledgeDatabase.release(context, f.name)
        val reopened = AgentKnowledgeDatabase.shared(context, f.name, f.legacy)
        val ledger = reopened.vectors(spec)
        assertEquals("existing v2 knowledge", requireNotNull(ledger.nextJob()).item.content)
        finish(ledger, FixtureEncoder(spec))
        requireNotNull(ledger.page("first")).use { assertEquals(1, it.total) }
    }

    @Test fun moreThanAThousandDocumentsCompleteWithoutTheOldFiveHundredLimit() = isolated { f ->
        val started = android.os.SystemClock.elapsedRealtime()
        f.store.replaceSource("source", (1..1201).map { item("scale-$it", "document $it") })
        val ledger = f.db.vectors(spec)
        finish(ledger, FixtureEncoder(spec))
        f.db.access { sql ->
            sql.rawQuery("SELECT count(*) FROM knowledge_vector_docs WHERE complete=1", null).use {
                assertTrue(it.moveToFirst()); assertEquals(1201, it.getInt(0))
            }
            sql.rawQuery("SELECT count(*) FROM knowledge_vector_queue", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            }
            sql.rawQuery("EXPLAIN QUERY PLAN SELECT item_key FROM knowledge_vector_queue WHERE model_key=? ORDER BY item_key LIMIT 1",
                arrayOf(f.db.key("vector-model", spec.identity))).use {
                assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("SEARCH knowledge_vector_queue"))
            }
        }
        requireNotNull(ledger.page("scale-1")).close()
        requireNotNull(ledger.page("scale-1201")).close()
        assertEquals(1201L, f.store.stats().itemCount)
        println("KNOWLEDGE_VECTOR_SCALE documents=1201 elapsed_ms=${android.os.SystemClock.elapsedRealtime() - started}")
    }
}
