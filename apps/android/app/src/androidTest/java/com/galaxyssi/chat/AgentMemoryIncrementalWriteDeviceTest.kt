package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AgentMemoryIncrementalWriteDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }
    private fun ciphertext(f: MemoryDeletionDeviceFixture, id: String): String = f.sql().use { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key = ?", arrayOf(AgentPersonalMemoryRows.key(id))).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }
    private fun removeLookupMarker(f: MemoryDeletionDeviceFixture): String {
        val meta = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        listOf("lookup_version", "lookup_generation", "lookup_key_stamp", "next_position").forEach(meta::remove)
        f.store.database.writeString(AgentPersonalMemoryRows.META, meta.toString())
        return meta.toString()
    }

    @Test fun ordinaryNewAndDuplicateWritesDoNotReadUnrelatedRows() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.database.writeString(AgentPersonalMemoryRows.key("memory-2"), "damaged unrelated row")
        val result = f.store.remember(deletionMemory(3))
        assertEquals("memory-3", result.item!!.id)
        assertTrue(f.reopen().remember(deletionMemory(4).copy(key = "key-3", value = result.item!!.value)).duplicate)
        assertEquals(3, f.store.count())
        assertEquals(2, f.store.findById("memory-3")!!.evidenceCount)
        assertNotNull(runCatching { f.store.loadItems() }.exceptionOrNull())
    }

    @Test fun indexedDuplicateMergesEvidenceWithoutRewritingAnotherCiphertext() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        val unchanged = ciphertext(f, "memory-2")
        val result = f.store.remember(deletionMemory(3).copy(key = "key-1", value = deletionMemory(1).value))
        assertTrue(result.duplicate)
        assertEquals("memory-1", result.item!!.id)
        assertEquals(2, result.item!!.evidenceCount)
        assertEquals(unchanged, ciphertext(f, "memory-2"))
        assertEquals(2, f.store.count())
    }

    @Test fun newRowsRetainTheExistingCanonicalStorageBounds() = fixture { f ->
        val item = deletionMemory(1).copy(value = "  value  ", key = "  KEY ! ", version = 0, confidence = 2.0,
            evidenceCount = 20_000, lastConfirmedAtMillis = -1, lastAccessedAtMillis = -1, expiresAtMillis = -1,
            whyRemembered = "w".repeat(2_000), originConversationId = "c".repeat(500), originEventId = "e".repeat(500))
        f.store.remember(item)
        val raw = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.key(item.id), "")).getJSONObject("item")
        assertEquals("value", raw.getString("value"))
        assertEquals("key", raw.getString("key"))
        assertEquals(1, raw.getInt("version"))
        assertEquals(1.0, raw.getDouble("confidence"), 0.0)
        assertEquals(10_000, raw.getInt("evidence_count"))
        assertEquals(0L, raw.getLong("last_confirmed_at_millis"))
        assertEquals(0L, raw.getLong("last_accessed_at_millis"))
        assertEquals(0L, raw.getLong("expires_at_millis"))
        assertEquals(1_000, raw.getString("why_remembered").length)
        assertEquals(160, raw.getString("origin_conversation_id").length)
        assertEquals(160, raw.getString("origin_event_id").length)
        assertTrue(f.store.remember(item.copy(id = "same-key-again")).duplicate)
    }

    @Test fun replacingDamagedPayloadDoesNotLeaveStaleLookupMembership() = fixture { f ->
        f.store.remember(deletionMemory(1))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val row = JSONObject(f.store.database.readString(key, ""))
        row.getJSONObject("item").put("value", "")
        f.store.database.writeString(key, row.toString())
        val meta = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        val indexes = f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX)
        assertNotNull(runCatching { f.store.saveItems(listOf(deletionMemory(1).copy(key = "changed"))) }.exceptionOrNull())
        assertEquals(row.toString(), f.store.database.readString(key, ""))
        assertEquals(meta, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        assertEquals(indexes, f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
    }

    @Test fun indexedConflictUpdatesBothCandidatesAndActiveCount() = fixture { f ->
        f.store.remember(deletionMemory(1))
        val result = f.store.remember(deletionMemory(2).copy(key = "key-1"))
        assertEquals(2, result.conflict!!.candidates.size)
        assertEquals(0, f.reopen().count())
        assertEquals(result.conflict!!.groupId, f.reopen().findById("memory-1")!!.conflictGroupId)
        val third = f.store.remember(deletionMemory(3).copy(key = "key-1"))
        assertEquals(3, third.conflict!!.candidates.size)
        assertEquals(3, third.item!!.version)
    }

    @Test fun ordinaryFullSavePreservesUnchangedLookupKeysAndCiphertext() = fixture { f ->
        val items = (0 until 3).map { deletionMemory(it) }
        f.store.saveItems(items)
        fun lookups(): Map<String, String> = f.sql().use { sql ->
            sql.rawQuery("SELECT storage_key, encrypted_value FROM encrypted_values WHERE storage_key LIKE ? ORDER BY storage_key",
                arrayOf(AgentPersonalMemoryRows.LOOKUP_PREFIX + "%")).use { rows ->
                buildMap { while (rows.moveToNext()) put(rows.getString(0), rows.getString(1)) }
            }
        }
        val before = lookups()
        assertEquals(3, before.size)
        f.store.saveItems(items.map { it.copy(lastAccessedAtMillis = 100, important = true) })
        assertEquals(before, lookups())
        assertTrue(f.store.remember(items.first().copy(id = "duplicate")).duplicate)
        assertEquals(before, lookups())
    }

    @Test fun scopedAndPrivateMemoriesDoNotCrossIdentityBoundaries() = fixture { f ->
        var id = 0
        AgentMemoryScope.entries.forEach { scope ->
            for (scopeId in listOf("a:b", "a")) {
                val item = deletionMemory(id++).copy(key = "same-key", value = "same", scope = scope, scopeId = scopeId, privateMemory = true)
                assertFalse(f.store.remember(item).duplicate)
                assertTrue(f.store.remember(item.copy(id = "duplicate-${item.id}")).duplicate)
            }
        }
        assertEquals(id, f.store.count())
        f.sql().use { sql ->
            sql.rawQuery("SELECT storage_key, encrypted_value FROM encrypted_values", null).use { rows ->
                while (rows.moveToNext()) {
                    assertFalse(rows.getString(0).contains("same-key"))
                    assertFalse(rows.getString(0).contains("a:b"))
                    assertTrue(AgentStorageCipher.isEncrypted(rows.getString(1)))
                }
            }
        }
    }

    @Test fun unkeyedUnicodeDuplicatesKeepEqualsIgnoreCaseBehaviorOnAndroid() = fixture { f ->
        val pairs = listOf("I" to "\u0131", "i" to "\u0130", "\u03c2" to "\u03c3", "\u017f" to "s", "\u1e9e" to "\u00df")
        pairs.forEachIndexed { index, (a, b) ->
            val first = deletionMemory(index).copy(key = "", value = a, scopeId = "pair-$index")
            f.store.remember(first)
            val result = f.store.remember(first.copy(id = "next-$index", value = b))
            assertEquals(a.equals(b, ignoreCase = true), result.duplicate)
        }
        f.store.remember(deletionMemory(50).copy(key = "", value = "\u00df", scopeId = "sharp-s"))
        assertFalse(f.store.remember(deletionMemory(51).copy(key = "", value = "ss", scopeId = "sharp-s")).duplicate)
    }

    @Test fun lookupBackfillUsesPagesAndPreservesOriginalRows() = fixture { f ->
        f.store.saveItems((0 until 257).map { deletionMemory(it) })
        val original = ciphertext(f, "memory-256")
        removeLookupMarker(f)
        f.store.remember(deletionMemory(300))
        assertEquals(original, ciphertext(f, "memory-256"))
        assertEquals(258, f.reopen().count())
        assertEquals(258, f.store.database.countKeys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
        assertTrue(f.store.remember(deletionMemory(301).copy(key = "key-256", value = deletionMemory(256).value)).duplicate)
    }

    @Test fun failedLookupBackfillKeepsOldRowsAndMetadata() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val original = ciphertext(f, "memory-1")
        val meta = removeLookupMarker(f)
        val lookups = f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX)
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_lookup_abort BEFORE INSERT ON encrypted_values WHEN NEW.storage_key = 'personal-memory:v3:metadata' BEGIN SELECT RAISE(ABORT, 'test_lookup_abort'); END")
            try {
                assertNotNull(runCatching { f.store.remember(deletionMemory(2)) }.exceptionOrNull())
                assertEquals(original, ciphertext(f, "memory-1"))
                assertEquals(meta, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
                assertEquals(lookups, f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
            } finally { sql.execSQL("DROP TRIGGER test_lookup_abort") }
        }
        assertEquals("memory-2", f.reopen().remember(deletionMemory(2)).item!!.id)
    }

    @Test fun failedNewRecordCommitRollsBackBodyLookupAndCounts() = fixture { f ->
        f.store.remember(deletionMemory(1))
        val meta = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        val indexes = f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX)
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_delta_abort BEFORE INSERT ON encrypted_values WHEN NEW.storage_key = 'personal-memory:v3:metadata' BEGIN SELECT RAISE(ABORT, 'test_delta_abort'); END")
            try {
                assertNotNull(runCatching { f.store.remember(deletionMemory(2)) }.exceptionOrNull())
                assertNull(f.reopen().findById("memory-2"))
                assertEquals(meta, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
                assertEquals(indexes, f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
            } finally { sql.execSQL("DROP TRIGGER test_delta_abort") }
        }
    }

    @Test fun collidingNewIdCannotOverwriteAnUnrelatedIdentity() = fixture { f ->
        val original = f.store.remember(deletionMemory(1)).item!!
        assertNotNull(runCatching { f.store.remember(original.copy(key = "other", value = "different")) }.exceptionOrNull())
        assertEquals(original, f.reopen().findById(original.id))
        assertEquals(1, f.store.count())
    }

    @Test fun corruptLookupOrKeyStampCannotBecomeFalseAbsence() = fixture { f ->
        f.store.remember(deletionMemory(1))
        val key = f.store.database.keys(AgentPersonalMemoryRows.LOOKUP_PREFIX).single()
        f.store.database.writeString(key, "missing-id")
        assertNotNull(runCatching { f.store.remember(deletionMemory(2).copy(key = "key-1")) }.exceptionOrNull())
        val meta = JSONObject(f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        f.store.database.writeString(AgentPersonalMemoryRows.META, meta.put("lookup_key_stamp", "invalid").toString())
        assertNotNull(runCatching { f.store.remember(deletionMemory(3)) }.exceptionOrNull())
        assertEquals(1, f.store.count())
    }

    @Test fun replacementRebindAndDeletionRefreshLookupMembership() = fixture { f ->
        val item = deletionMemory(1).copy(scope = AgentMemoryScope.CONVERSATION, scopeId = "old")
        f.store.remember(item)
        assertEquals(1, f.store.rebindConversationScope("old", "new"))
        assertFalse(f.store.remember(item.copy(id = "new-old")).duplicate)
        assertTrue(f.store.remember(item.copy(id = "duplicate", scopeId = "new")).duplicate)
        assertTrue(f.store.deleteById("memory-1"))
        assertFalse(f.store.remember(item.copy(id = "replacement", scopeId = "new")).duplicate)
        assertEquals(2, f.store.database.countKeys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
    }

    @Test fun moreThanOneThousandHistoricalRowsSurviveOrdinaryWritesAndEdits() = fixture { f ->
        val history = (0 until 1_201).map { deletionMemory(it).copy(status = AgentMemoryStatus.SUPERSEDED) }
        f.store.saveItems(history)
        f.store.remember(deletionMemory(2_000))
        assertNotNull(f.store.update("memory-2000", "edited"))
        assertEquals(1, f.store.count())
        assertEquals(1_202, f.reopen().snapshot().historyItems.size)
        assertEquals(1_203, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
    }

    @Test fun concurrentWritersMergeDuplicatesWithoutLosingEvidence() = fixture { f ->
        f.store.remember(deletionMemory(1))
        val workers = Executors.newFixedThreadPool(2)
        try {
            val jobs = (2..3).map { id -> workers.submit {
                f.reopen().remember(deletionMemory(id).copy(key = "key-1", value = deletionMemory(1).value))
            } }
            jobs.forEach { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, f.store.count())
            assertEquals(3, f.store.findById("memory-1")!!.evidenceCount)
        } finally { workers.shutdownNow() }
    }

    @Test fun backdatedMemoriesStillAppearInTimestampOrderInPublicSnapshot() = fixture { f ->
        f.store.remember(deletionMemory(1).copy(timestampMillis = 100))
        f.store.remember(deletionMemory(2).copy(timestampMillis = 1))
        assertEquals(listOf("memory-1", "memory-2"), f.reopen().snapshot().activeItems.map { it.id })
    }

    @Test fun actualNewRecordAndDuplicateWriteLatencyAtTwoCardinalities() {
        for (size in listOf(1_201, 10_001)) fixture { f ->
            f.store.saveItems((0 until size).map { deletionMemory(it) })
            val fresh = mutableListOf<Double>()
            val duplicate = mutableListOf<Double>()
            repeat(100) { sample ->
                val item = deletionMemory(size + sample)
                val start = SystemClock.elapsedRealtimeNanos()
                assertFalse(f.store.remember(item).duplicate)
                val middle = SystemClock.elapsedRealtimeNanos()
                assertTrue(f.store.remember(item.copy(id = "duplicate-$sample")).duplicate)
                val end = SystemClock.elapsedRealtimeNanos()
                fresh.add((middle - start) / 1_000_000.0)
                duplicate.add((end - middle) / 1_000_000.0)
            }
            assertEquals(size + 100, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
            assertEquals(size + 100, f.store.database.countKeys(AgentPersonalMemoryRows.LOOKUP_PREFIX))
            assertEquals(size + 100, f.store.count())
            fun report(values: List<Double>): String {
                val sorted = values.sorted()
                return "p50=${sorted[49]} p95=${sorted[94]} p99=${sorted[98]} max=${sorted.last()} misses100=${values.count { it >= 100 }} misses200=${values.count { it > 200.0 }} budgetMs=200"
            }
            Log.i("GalaxySSIMemoryWriteTest", "rowsBefore=$size samples=100 newMs=${report(fresh)} duplicateMs=${report(duplicate)}")
        }
    }
}
