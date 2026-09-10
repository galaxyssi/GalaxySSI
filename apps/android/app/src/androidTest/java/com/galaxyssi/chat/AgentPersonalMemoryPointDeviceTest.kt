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
class AgentPersonalMemoryPointDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }

    @Test fun flagUpdatesAndPointReadsDoNotScanAnUnrelatedDamagedRow() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.database.writeString(AgentPersonalMemoryRows.key("memory-2"), "damaged unrelated row")
        assertEquals(deletionMemory(1), f.store.findById("memory-1"))
        assertTrue(f.store.setImportant("memory-1", true))
        assertTrue(f.store.setPrivate("memory-1", true))
        assertEquals(deletionMemory(1).copy(important = true, privateMemory = true), f.reopen().findById("memory-1"))
        assertNotNull(runCatching { f.reopen().loadItems() }.exceptionOrNull())
    }

    @Test fun missingIdIsNotAnAliasForTheFirstOrMostRecentRow() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        assertNull(f.store.findById("missing"))
        assertNull(f.store.findById(""))
        assertFalse(f.store.setImportant("missing", true))
        assertFalse(f.store.setPrivate("missing", true))
        assertEquals(deletionMemory(1), f.store.findById("memory-1"))
    }

    @Test fun historicalImportanceIsRejectedButHistoricalPrivacyStillWorks() = fixture { f ->
        val old = deletionMemory(1).copy(status = AgentMemoryStatus.SUPERSEDED)
        f.store.saveItems(listOf(old))
        assertFalse(f.store.setImportant(old.id, true))
        assertTrue(f.store.setPrivate(old.id, true))
        assertEquals(old.copy(privateMemory = true), f.reopen().findById(old.id))
        assertEquals(0, f.store.count())
    }

    @Test fun repeatedUnchangedFlagsDoNotRewriteTheMetadataRevision() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val before = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        assertTrue(f.store.setImportant("memory-1", false))
        assertTrue(f.store.setPrivate("memory-1", false))
        assertEquals(before, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
    }

    @Test fun failedMetadataCommitRollsBackTheFlagUpdate() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val before = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_point_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key = 'personal-memory:v3:metadata' BEGIN SELECT RAISE(ABORT, 'test_point_abort'); END")
            try {
                assertNotNull(runCatching { f.store.setPrivate("memory-1", true) }.exceptionOrNull())
                assertEquals(deletionMemory(1), f.reopen().findById("memory-1"))
                assertEquals(before, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
            } finally { sql.execSQL("DROP TRIGGER test_point_abort") }
        }
    }

    @Test fun mismatchedIdentityOrUnreadableMetadataCannotBeOverwritten() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val row = JSONObject(f.store.database.readString(key, ""))
        row.getJSONObject("item").put("id", "different")
        f.store.database.writeString(key, row.toString())
        assertNotNull(runCatching { f.store.findById("memory-1") }.exceptionOrNull())
        assertNotNull(runCatching { f.store.setPrivate("memory-1", true) }.exceptionOrNull())
        f.store.database.writeString(AgentPersonalMemoryRows.META, "corrupt")
        assertNotNull(runCatching { f.store.setImportant("memory-1", true) }.exceptionOrNull())
    }

    @Test fun concurrentDifferentFlagsDoNotLoseEachOthersChanges() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val workers = Executors.newFixedThreadPool(2)
        try {
            val jobs = listOf(workers.submit { assertTrue(f.reopen().setImportant("memory-1", true)) },
                workers.submit { assertTrue(f.reopen().setPrivate("memory-1", true)) })
            jobs.forEach { it.get(30, TimeUnit.SECONDS) }
            assertEquals(deletionMemory(1).copy(important = true, privateMemory = true), f.store.findById("memory-1"))
        } finally { workers.shutdownNow() }
    }

    @Test fun pointOperationLatencyIsMeasuredWithRealStoredRows() {
        for (size in listOf(1_201, 10_001)) fixture { f ->
            f.store.saveItems((0 until size).map { deletionMemory(it) })
            val reads = mutableListOf<Double>()
            val writes = mutableListOf<Double>()
            repeat(100) { sample ->
                val id = "memory-${sample * 97 % size}"
                val start = SystemClock.elapsedRealtimeNanos()
                assertEquals(id, f.store.findById(id)?.id)
                val middle = SystemClock.elapsedRealtimeNanos()
                assertTrue(f.store.setImportant(id, true))
                val end = SystemClock.elapsedRealtimeNanos()
                reads.add((middle - start) / 1_000_000.0)
                writes.add((end - middle) / 1_000_000.0)
            }
            fun report(values: List<Double>): String {
                val sorted = values.sorted()
                return "p50=${sorted[49]} p95=${sorted[94]} p99=${sorted[98]} max=${sorted.last()} misses100=${values.count { it >= 100.0 }}"
            }
            assertEquals(size, f.store.count())
            Log.i("GalaxySSIMemoryPointTest", "rows=$size samples=100 readMs=${report(reads)} writeMs=${report(writes)}")
        }
    }
}
