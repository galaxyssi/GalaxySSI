package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryRecallAccessDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }

    private fun ciphertext(f: MemoryDeletionDeviceFixture, key: String): String = f.sql().use { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?", arrayOf(key)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }

    @Test fun selectedAccessDoesNotReadOrRewriteAnUnrelatedDamagedBody() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.browseCounts()
        val other = AgentPersonalMemoryRows.key("memory-2")
        f.store.database.writeString(other, "unreadable unrelated body")
        val untouched = ciphertext(f, other)
        assertEquals(1, AgentPersonalMemoryRows(f.store.database).refreshAccess(setOf("memory-1"), 10_000))
        assertEquals(deletionMemory(1).copy(lastAccessedAtMillis = 10_000), f.reopen().findById("memory-1"))
        assertEquals(untouched, ciphertext(f, other))
        assertEquals(2L, f.reopen().browseCounts().active)
    }

    @Test fun accessPreservesTheExistingWriteIntervalAndOriginalTimestamp() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val rows = AgentPersonalMemoryRows(f.store.database)
        assertEquals(1, rows.refreshAccess(setOf("memory-1"), 10_000))
        val revision = ciphertext(f, AgentPersonalMemoryRows.META)
        val body = ciphertext(f, AgentPersonalMemoryRows.key("memory-1"))
        assertEquals(0, rows.refreshAccess(setOf("memory-1"), 309_999))
        assertEquals(0, rows.refreshAccess(setOf("memory-1"), 9_999))
        assertEquals(revision, ciphertext(f, AgentPersonalMemoryRows.META))
        assertEquals(body, ciphertext(f, AgentPersonalMemoryRows.key("memory-1")))
        assertEquals(1, rows.refreshAccess(setOf("memory-1"), 310_000))
        assertEquals(deletionMemory(1).copy(lastAccessedAtMillis = 310_000), f.reopen().findById("memory-1"))
    }

    @Test fun deletedPrivateExpiredAndHistoricalRowsAreNotRefreshed() = fixture { f ->
        val items = listOf(deletionMemory(1).copy(privateMemory = true),
            deletionMemory(2).copy(expiresAtMillis = 100),
            deletionMemory(3).copy(status = AgentMemoryStatus.SUPERSEDED),
            deletionMemory(4).copy(key = "conflict", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "g"),
            deletionMemory(5).copy(key = "conflict", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "g"))
        f.store.saveItems(items)
        val before = ciphertext(f, AgentPersonalMemoryRows.META)
        assertEquals(0, AgentPersonalMemoryRows(f.store.database).refreshAccess(items.map { it.id }.toSet() + "missing", 10_000))
        assertEquals(before, ciphertext(f, AgentPersonalMemoryRows.META))
        assertEquals(items, f.reopen().loadItems())
    }

    @Test fun failedMetadataCommitRollsBackAllSelectedAccessUpdates() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.browseCounts()
        val keys = listOf(AgentPersonalMemoryRows.key("memory-1"), AgentPersonalMemoryRows.key("memory-2"), AgentPersonalMemoryRows.META)
        val before = keys.map { ciphertext(f, it) }
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_access_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key='personal-memory:v3:metadata' BEGIN SELECT RAISE(ABORT,'access commit failure'); END")
            try {
                assertNotNull(runCatching { AgentPersonalMemoryRows(f.store.database).refreshAccess(setOf("memory-1", "memory-2"), 10_000) }.exceptionOrNull())
            } finally { sql.execSQL("DROP TRIGGER test_access_abort") }
        }
        assertEquals(before, keys.map { ciphertext(f, it) })
        assertEquals(2L, f.reopen().browseCounts().active)
    }

    @Test fun corruptSelectedBodyCannotPartiallyRefreshAnotherRow() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.database.writeString(AgentPersonalMemoryRows.key("memory-2"), "invalid selected payload")
        val before = ciphertext(f, AgentPersonalMemoryRows.key("memory-1"))
        val revision = ciphertext(f, AgentPersonalMemoryRows.META)
        assertNotNull(runCatching { AgentPersonalMemoryRows(f.store.database).refreshAccess(linkedSetOf("memory-1", "memory-2"), 10_000) }.exceptionOrNull())
        assertEquals(before, ciphertext(f, AgentPersonalMemoryRows.key("memory-1")))
        assertEquals(revision, ciphertext(f, AgentPersonalMemoryRows.META))
    }

    @Test fun actualRecallUpdatesOnlyTheReturnedMemory() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, "project-neptune release notes"), deletionMemory(2, "unrelated accounting")))
        f.store.browseCounts()
        val other = ciphertext(f, AgentPersonalMemoryRows.key("memory-2"))
        assertEquals(listOf("memory-1"), f.store.recall("project-neptune").map { it.id })
        assertTrue(f.reopen().findById("memory-1")!!.lastAccessedAtMillis > 0)
        assertEquals(0L, f.reopen().findById("memory-2")!!.lastAccessedAtMillis)
        assertEquals(other, ciphertext(f, AgentPersonalMemoryRows.key("memory-2")))
        assertEquals(2L, f.reopen().browseCounts().active)
    }

    @Test fun selectedAccessLatencyUsesRealCardinalitiesAndReportsBothBudgets() {
        for (size in listOf(1_201, 10_001)) fixture { f ->
            f.store.saveItems((0 until size).map(::deletionMemory))
            f.store.browseCounts()
            val rows = AgentPersonalMemoryRows(f.store.database)
            val one = mutableListOf<Double>(); val eight = mutableListOf<Double>()
            repeat(100) { sample ->
                val now = 1_000_000L + sample * 600_000L
                val selected = (0 until 8).map { "memory-${(sample * 97 + it) % size}" }.toSet()
                val started = SystemClock.elapsedRealtimeNanos()
                assertEquals(1, rows.refreshAccess(setOf(selected.first()), now))
                val middle = SystemClock.elapsedRealtimeNanos()
                assertEquals(8, rows.refreshAccess(selected, now + 300_000L))
                val finished = SystemClock.elapsedRealtimeNanos()
                one += (middle - started) / 1_000_000.0; eight += (finished - middle) / 1_000_000.0
            }
            fun report(name: String, values: List<Double>) {
                val sorted = values.sorted()
                Log.i("GalaxySSIMemoryAccess", "rows=$size operation=$name samples=100 p50=${sorted[49]} p95=${sorted[94]} " +
                    "p99=${sorted[98]} max=${sorted.last()} misses100=${values.count { it >= 100.0 }} misses200=${values.count { it > 200.0 }} budgetMs=200")
                Log.i("GalaxySSIMemoryAccess", "rows=$size operation=$name raw_ms=${values.joinToString(",")}")
            }
            assertEquals(size, f.reopen().count())
            report("access1", one); report("access8", eight)
        }
    }
}
