package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.WorkManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException

@RunWith(AndroidJUnit4::class)
class AgentMemorySegmentWorkDeviceTest {
    private fun fixture(test: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { test(f) } finally {
            f.clear()
            repeat(8) { f.store.database.maintainMemorySegments(32, 32) }
        }
    }
    private fun key(i: Int) = AgentPersonalMemoryRows.key("work-$i")
    private fun text(i: Int) = "\u8bb0\u5fc6\u540e\u53f0\u6574\u7406-$i ".repeat(1500)
    private fun files(f: MemoryDeletionDeviceFixture) = File(f.store.database.storageIdentity + ".segments")
        .walkTopDown().filter { it.extension == "seg" }.toList()
    private fun pointer(f: MemoryDeletionDeviceFixture, key: String) = f.sql().use { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?", arrayOf(key)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }

    @Test fun absentCatalogDoesNotCreateAStoreOrScanMemory() = fixture { f ->
        val path = File(f.store.database.storageIdentity)
        assertFalse(path.exists())
        assertEquals(MemorySegmentSweep.Outcome.COMPLETE, AgentMemorySegmentWork.run(f.context) { false })
        assertFalse(path.exists())
        assertFalse(File(path.absolutePath + ".segments.catalog.db").exists())
    }

    @Test fun foregroundYieldPreservesReferencesThenBackgroundSweepCompletes() = fixture { f ->
        val db = f.store.database
        repeat(8) { db.writeString(key(it), text(it)) }
        repeat(6) { db.remove(key(it)) }
        val before = pointer(f, key(6))
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, AgentMemorySegmentWork.run(f.context) { true })
        assertEquals(before, pointer(f, key(6)))
        var outcome = MemorySegmentSweep.Outcome.DEFERRED
        repeat(10) { if (outcome != MemorySegmentSweep.Outcome.COMPLETE) outcome = AgentMemorySegmentWork.run(f.context) { false } }
        assertEquals(MemorySegmentSweep.Outcome.COMPLETE, outcome)
        assertNotEquals(before, pointer(f, key(6)))
        assertEquals(1, files(f).size)
        assertEquals(text(6), db.readString(key(6), ""))
        assertEquals(text(7), db.readString(key(7), ""))
    }

    @Test fun activeSqlTransactionMakesMaintenanceYieldWithoutWaiting() = fixture { f ->
        val db = f.store.database
        db.writeString(key(1), text(1))
        val pool = Executors.newSingleThreadExecutor()
        try {
            db.indexedTransaction {
                val future = pool.submit<AgentMemorySegmentMaintenance.Result?> { db.tryMaintainMemorySegments {} }
                assertNull(future.get(1, TimeUnit.SECONDS))
            }
            assertNotNull(db.tryMaintainMemorySegments {})
            assertEquals(text(1), db.readString(key(1), ""))
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun foregroundDuringCopyRollsBackAndTheNextInvocationRecovers() = fixture { f ->
        val random = java.util.Random(37)
        val data = buildString { repeat(350_000) { append(('!'.code + random.nextInt(90)).toChar()) } }
        val db = f.store.database
        repeat(3) { db.writeString(key(it), data) }
        repeat(2) { db.remove(key(it)) }
        val before = pointer(f, key(2))
        var checks = 0
        val stopped = CancellationException("synthetic foreground transition")
        assertSame(stopped, runCatching {
            db.tryMaintainMemorySegments { if (++checks == 6) throw stopped }
        }.exceptionOrNull())
        assertEquals(before, pointer(f, key(2)))
        assertEquals(data, db.readString(key(2), ""))
        repeat(8) { AgentMemorySegmentWork.run(f.context) { false } }
        assertEquals(data, db.readString(key(2), ""))
        assertEquals(1, files(f).size)
    }

    @Test fun periodicRequestIsDurableAndDuplicateEnqueuesKeepTheSameJob() = fixture { f ->
        val name = "test-memory-segment-work-${UUID.randomUUID()}"
        val manager = WorkManager.getInstance(f.context)
        try {
            AgentMemorySegmentWork.enqueue(f.context, name).result.get(30, TimeUnit.SECONDS)
            val first = manager.getWorkInfosForUniqueWork(name).get(10, TimeUnit.SECONDS).single()
            assertEquals(androidx.work.WorkInfo.State.ENQUEUED, first.state)
            AgentMemorySegmentWork.enqueue(f.context, name).result.get(30, TimeUnit.SECONDS)
            val second = manager.getWorkInfosForUniqueWork(name).get(10, TimeUnit.SECONDS).single()
            assertEquals(first.id, second.id)
            assertEquals(androidx.work.WorkInfo.State.ENQUEUED, second.state)
        } finally { manager.cancelUniqueWork(name).result.get(30, TimeUnit.SECONDS) }
    }
}
