package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryIndexedRecallDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }
    private fun query(f: MemoryDeletionDeviceFixture, text: String, now: Long = System.currentTimeMillis()): Pair<AgentMemoryRecallQuery, List<AgentMemoryItem>> {
        val query = AgentMemoryRecallQuery(f.store.database)
        return query to query.search(text, now, 8, scheduleBackfill = false)
    }
    private fun state(f: MemoryDeletionDeviceFixture) = f.store.database.indexedTransaction { AgentMemoryRecallIndex(f.store.database).state(it) }

    @Test fun selectiveRecallDoesNotReadAnUnrelatedDamagedBody() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting"), deletionMemory(2, "accounting")))
        f.store.database.writeString(AgentPersonalMemoryRows.key("memory-2"), "damaged unrelated body")
        val (diagnostic, result) = query(f, "nebularouting")
        assertTrue(diagnostic.usedIndex); assertEquals(1L, diagnostic.decryptedRows)
        assertEquals(listOf("memory-1"), result.map { it.id })
        assertEquals(listOf("memory-1"), f.store.recall("nebularouting").map { it.id })
    }

    @Test fun newMutationEditingPrivacyAndDeletionKeepPostingsCurrent() = fixture { f ->
        f.store.remember(deletionMemory(1, "nebularouting"))
        assertEquals(1, query(f, "nebularouting").second.size)
        assertTrue(f.store.setPrivate("memory-1", true))
        assertTrue(query(f, "nebularouting").second.isEmpty())
        assertTrue(f.store.setPrivate("memory-1", false))
        val updated = f.store.update("memory-1", "quartzgeometry")!!.item!!
        assertTrue(query(f, "nebularouting").second.isEmpty())
        assertEquals(listOf(updated.id), query(f, "quartzgeometry").second.map { it.id })
        assertTrue(f.store.deleteById(updated.id))
        assertTrue(query(f, "quartzgeometry").second.isEmpty())
        assertEquals(0, f.reopen().count())
    }

    @Test fun replacementDeletesAfterMetadataWithoutLeavingStaleCandidates() = fixture { f ->
        f.store.saveItems((0 until 30).map { deletionMemory(it, "retiredmarker") })
        f.store.saveItems(listOf(deletionMemory(200, "replacementmarker")))
        assertTrue(query(f, "retiredmarker").second.isEmpty())
        assertEquals(listOf("memory-200"), query(f, "replacementmarker").second.map { it.id })
    }

    @Test fun manyCandidatePagesKeepLateWinnersAndStableTies() = fixture { f ->
        val items = (0 until 257).map { deletionMemory(it, "shared marker").copy(important = it == 256, confidence = (it % 10) / 10.0) }
        f.store.saveItems(items)
        val now = System.currentTimeMillis()
        val expected = items.withIndex().sortedWith(compareByDescending<IndexedValue<AgentMemoryItem>> {
            AgentMemoryRecallRanking.score(it.value, "shared", now)
        }.thenByDescending { it.value.important }.thenByDescending { it.value.timestampMillis }.thenBy { it.index }).take(8).map { it.value.id }
        val (diagnostic, result) = query(f, "shared", now)
        assertTrue(diagnostic.usedIndex); assertEquals(257L, diagnostic.decryptedRows)
        assertEquals(expected, result.map { it.id })
    }

    @Test fun candidateValidationRejectsPrivateTamperingAndExpiredRows() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting"), deletionMemory(2, "nebularouting").copy(expiresAtMillis = 9)))
        assertEquals(listOf("memory-1"), query(f, "nebularouting", 10).second.map { it.id })
        val key = AgentPersonalMemoryRows.key("memory-1")
        val row = JSONObject(f.store.database.readString(key, ""))
        row.getJSONObject("item").put("private_memory", true)
        f.store.database.writeString(key, row.toString())
        assertNotNull(runCatching { query(f, "nebularouting") }.exceptionOrNull())
    }

    @Test fun failedDocumentInsertionRollsBackSourceAndIndexes() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting")))
        val before = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_recall_abort BEFORE INSERT ON ${AgentMemoryRecallIndex.DOCS} BEGIN SELECT RAISE(ABORT,'index failure'); END")
            try { assertNotNull(runCatching { f.store.remember(deletionMemory(2, "quartzgeometry")) }.exceptionOrNull()) }
            finally { sql.execSQL("DROP TRIGGER test_recall_abort") }
        }
        assertEquals(before, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        assertNull(f.reopen().findById("memory-2"))
        assertEquals(1, query(f, "nebularouting").second.size)
        assertTrue(query(f, "quartzgeometry").second.isEmpty())
    }

    @Test fun indexContainsOnlyKeyedTokensAndIntegerPostings() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "sensitive-private-test-value")))
        f.sql().use { sql ->
            sql.rawQuery("SELECT token FROM ${AgentMemoryRecallIndex.TERMS}", null).use { c ->
                assertTrue(c.count > 0)
                while (c.moveToNext()) assertTrue(c.getString(0).matches(Regex("[A-Za-z0-9_-]{43}")))
            }
            sql.rawQuery("EXPLAIN QUERY PLAN SELECT doc_id FROM ${AgentMemoryRecallIndex.POSTINGS} WHERE term_id=1 AND doc_id>0 ORDER BY doc_id LIMIT 16", null).use { c ->
                val plan = buildList { while (c.moveToNext()) add(c.getString(3)) }.joinToString(" ")
                assertTrue(plan, plan.contains("PRIMARY KEY")); assertFalse(plan, plan.contains("TEMP B-TREE"))
            }
        }
    }

    @Test fun interruptedBackfillResumesAndIncludesConcurrentMutations() = fixture { f ->
        f.store.saveItems((0 until 129).map { deletionMemory(it, "initial marker $it") })
        f.store.database.remove(AgentMemoryRecallIndex.MARKER)
        val original = state(f)
        assertFalse(original.ready)
        val fallback = query(f, "initial marker")
        assertFalse(fallback.first.usedIndex); assertEquals(129L, fallback.first.decryptedRows)
        assertFalse(AgentMemoryRecallIndex(f.store.database).backfillPage(original.generation, 16))
        val cursor = state(f).cursor
        assertTrue(cursor.isNotBlank())
        f.reopen().remember(deletionMemory(999, "nebularouting"))
        assertTrue(f.reopen().deleteById("memory-0"))
        val reopened = AgentMemoryRecallIndex(f.reopen().database)
        assertEquals(cursor, state(f).cursor)
        while (!reopened.backfillPage(original.generation, 16)) { }
        assertTrue(state(f).ready)
        assertEquals(listOf("memory-999"), query(f, "nebularouting").second.map { it.id })
        assertEquals(129, f.reopen().count())
        assertEquals(1L, query(f, "nebularouting").first.decryptedRows)
    }

    @Test fun failedBackfillRollsBackItsCursorAndCanRetry() = fixture { f ->
        f.store.saveItems((0 until 35).map { deletionMemory(it) })
        f.store.database.remove(AgentMemoryRecallIndex.MARKER)
        val initial = state(f)
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_backfill_abort BEFORE INSERT ON ${AgentMemoryRecallIndex.DOCS} BEGIN SELECT RAISE(ABORT,'backfill failure'); END")
            try { assertNotNull(runCatching { AgentMemoryRecallIndex(f.store.database).backfillPage(initial.generation) }.exceptionOrNull()) }
            finally { sql.execSQL("DROP TRIGGER test_backfill_abort") }
        }
        assertEquals("", state(f).cursor)
        while (!AgentMemoryRecallIndex(f.reopen().database).backfillPage(initial.generation)) { }
        assertTrue(state(f).ready)
        assertEquals(35, f.reopen().count())
    }

    @Test fun backgroundBackfillCompletesWithoutReplacingSourceData() = fixture { f ->
        f.store.saveItems((0 until 40).map { deletionMemory(it) })
        f.store.database.remove(AgentMemoryRecallIndex.MARKER)
        f.store.recall("unmatched")
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (!state(f).ready && SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
        assertTrue(state(f).ready); assertEquals(40, f.reopen().count())
    }

    @Test fun longReverseQueryAndSplitChineseTokensMatchExistingSemantics() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "rare-middle-value"), deletionMemory(2, "\u4e2d\u6587")))
        assertEquals(listOf("memory-1"), query(f, "prefix ".repeat(200) + "rare-middle-value").second.map { it.id })
        assertEquals(listOf("memory-2"), query(f, "\u4e2d \u6587").second.map { it.id })
    }

    @Test fun clearedOrReplacedGenerationCannotBeResurrectedByBackfill() = fixture { f ->
        f.store.saveItems((0 until 3).map { deletionMemory(it) })
        val old = state(f)
        f.store.database.remove(AgentMemoryRecallIndex.MARKER)
        val index = AgentMemoryRecallIndex(f.store.database)
        assertTrue(index.backfillPage(old.generation))
        assertFalse(f.store.database.contains(AgentMemoryRecallIndex.MARKER))
        val replacement = state(f)
        assertNotEquals(old.generation, replacement.generation)
        assertTrue(index.backfillPage(old.generation))
        assertEquals(replacement.generation, state(f).generation)
        assertEquals("", state(f).cursor)
    }

    @Test fun olderWriterRevisionInvalidatesStalePostingsBeforeRecall() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting"), deletionMemory(2, "accounting")))
        val oldGeneration = state(f).generation
        val key = AgentPersonalMemoryRows.key("memory-1")
        val body = JSONObject(f.store.database.readString(key, ""))
        body.getJSONObject("item").put("value", "quartzgeometry")
        val metadata = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.META, ""))
            .put("revision", java.util.UUID.randomUUID().toString())
        f.store.database.mutateStrings(mapOf(key to body.toString(), AgentPersonalMemoryRows.META to metadata.toString()))
        val (diagnostic, result) = query(f, "quartzgeometry")
        assertFalse(diagnostic.usedIndex); assertEquals(listOf("memory-1"), result.map { it.id })
        val replacement = state(f)
        assertNotEquals(oldGeneration, replacement.generation)
        while (!AgentMemoryRecallIndex(f.store.database).backfillPage(replacement.generation)) { }
        assertTrue(query(f, "nebularouting").second.isEmpty())
        assertTrue(query(f, "quartzgeometry").first.usedIndex)
    }

    @Test fun normalWriteCannotValidateAnOlderWritersStaleIndex() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting")))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val body = JSONObject(f.store.database.readString(key, ""))
        body.getJSONObject("item").put("value", "quartzgeometry")
        val metadata = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.META, ""))
            .put("revision", java.util.UUID.randomUUID().toString())
        f.store.database.mutateStrings(mapOf(key to body.toString(), AgentPersonalMemoryRows.META to metadata.toString()))
        f.store.setImportant("memory-1", true)
        val (diagnostic, result) = query(f, "quartzgeometry")
        assertFalse(diagnostic.usedIndex)
        assertEquals(listOf("memory-1"), result.map { it.id })
        val generation = state(f).generation
        while (!AgentMemoryRecallIndex(f.store.database).backfillPage(generation)) { }
        assertEquals(listOf("memory-1"), query(f, "quartzgeometry").second.map { it.id })
    }

    @Test fun legacyJsonMigrationCanCreateRecallMetadataAfterItsRows() = fixture { f ->
        val items = org.json.JSONArray().put(AgentMemoryItemCodec.encode(deletionMemory(1, "nebularouting")))
        f.store.database.writeString(AgentMemoryStorage.ITEMS, items.toString())
        assertEquals(listOf("memory-1"), f.store.recall("nebularouting").map { it.id })
        assertEquals(1, f.reopen().count())
    }

    @Test fun accessAndImportancePreserveTheEncryptedIndexMarker() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting")))
        fun ciphertext() = f.sql().use { sql ->
            sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?",
                arrayOf(AgentMemoryRecallIndex.MARKER)).use { check(it.moveToFirst()); it.getString(0) }
        }
        val before = ciphertext()
        val original = state(f).generation
        assertEquals(1, AgentPersonalMemoryRows(f.store.database).refreshAccess(setOf("memory-1"), 10_000))
        assertTrue(f.store.setImportant("memory-1", true))
        assertEquals(before, ciphertext())
        assertTrue(query(f, "nebularouting").first.usedIndex)
        assertEquals(original, state(f).generation)
    }

    @Test fun accessWriteDoesNotConcealAnOlderWritersContentChange() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "nebularouting")))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val body = JSONObject(f.store.database.readString(key, ""))
        body.getJSONObject("item").put("value", "quartzgeometry")
        val metadata = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.META, ""))
            .put("revision", java.util.UUID.randomUUID().toString())
        f.store.database.mutateStrings(mapOf(key to body.toString(), AgentPersonalMemoryRows.META to metadata.toString()))
        AgentPersonalMemoryRows(f.store.database).refreshAccess(setOf("memory-1"), 10_000)
        val (diagnostic, result) = query(f, "quartzgeometry")
        assertFalse(diagnostic.usedIndex)
        assertEquals(listOf("memory-1"), result.map { it.id })
    }

    @Test fun actualWarmRecallAndNewWriteLatencyAtRealCardinalities() {
        for (size in listOf(1_201, 10_001)) fixture { f ->
            f.store.saveItems((0 until size).map { deletionMemory(it, if (it == 0) "nebularouting" else "stored fact $it") })
            assertEquals(size, f.reopen().count())
            assertTrue(query(f, "nebularouting").first.usedIndex)
            assertEquals(1L, query(f, "nebularouting").first.decryptedRows)
            assertEquals(listOf("memory-0"), f.store.recall("nebularouting").map { it.id })
            val referenceStart = SystemClock.elapsedRealtimeNanos()
            val reference = f.store.loadItems().filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory && !it.isExpired(System.currentTimeMillis()) }
                .filter { f.store.lexicalScore(it, "nebularouting") > 0.0 }.sortedByDescending { f.store.score(it, "nebularouting") }.take(8)
            val referenceMillis = (SystemClock.elapsedRealtimeNanos() - referenceStart) / 1_000_000.0
            assertEquals(listOf("memory-0"), reference.map { it.id })
            Log.i("GalaxySSIRecallBench", "rows=$size operation=legacyScanReference samples=1 elapsedMs=$referenceMillis")
            val recall = mutableListOf<Double>(); val writes = mutableListOf<Double>()
            repeat(100) { sample ->
                val before = SystemClock.elapsedRealtimeNanos()
                assertEquals(listOf("memory-0"), f.store.recall("nebularouting").map { it.id })
                val middle = SystemClock.elapsedRealtimeNanos()
                assertNotNull(f.store.remember(deletionMemory(size + sample, "new stored fact $sample")).item)
                val end = SystemClock.elapsedRealtimeNanos()
                recall += (middle - before) / 1_000_000.0; writes += (end - middle) / 1_000_000.0
            }
            assertEquals(size + 100, f.reopen().count())
            fun report(name: String, values: List<Double>) {
                val ordered = values.sorted()
                Log.i("GalaxySSIRecallBench", "rows=$size operation=$name samples=100 p50=${ordered[49]} p95=${ordered[94]} p99=${ordered[98]} max=${ordered.last()} misses200=${values.count { it > 200.0 }}")
                Log.i("GalaxySSIRecallBench", "rows=$size operation=$name raw_ms=${values.joinToString(",")}")
            }
            report("warmRecall", recall); report("newWrite", writes)
            f.sql().use { sql ->
                fun scalar(statement: String): Long = sql.rawQuery(statement, null).use { check(it.moveToFirst()); it.getLong(0) }
                Log.i("GalaxySSIRecallBench", "rowsAfter=${size + 100} databaseBytes=${scalar("PRAGMA page_count") * scalar("PRAGMA page_size")} " +
                    "terms=${scalar("SELECT count(*) FROM ${AgentMemoryRecallIndex.TERMS}")} postings=${scalar("SELECT count(*) FROM ${AgentMemoryRecallIndex.POSTINGS}")}")
            }
        }
    }
}
