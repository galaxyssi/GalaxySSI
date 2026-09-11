package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentMemoryStreamingBackupDeviceTest {
    private val password = "fixture-only-passphrase".toCharArray()
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val fixture = MemoryDeletionDeviceFixture()
        try { block(fixture) } finally { fixture.clear() }
    }
    private fun backup(f: MemoryDeletionDeviceFixture): File = File(f.context.cacheDir, "${UUID.randomUUID()}.hcbak")

    @Test fun realRowsRoundTripAndUserFacingOrderIsPreserved() = fixture { f ->
        val input = (0 until 137).map { deletionMemory(it).copy(privateMemory = it % 3 == 0, important = it % 7 == 0,
            scope = AgentMemoryScope.CONVERSATION, scopeId = "Scope-${it % 4}", timestampMillis = (it % 5).toLong()) }
        f.store.saveItems(input)
        val file = backup(f)
        try {
            assertEquals(139L, AgentMemoryStreamingBackup.export(f.context, file, password))
            f.store.saveItems(listOf(deletionMemory(999)))
            AgentMemoryStreamingBackup.restore(f.context, file, password)
            assertEquals(input, f.reopen().loadItems())
        } finally { file.delete() }
    }

    @Test fun localDeletionAfterExportStillSuppressesTheOldBackup() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        val file = backup(f)
        try {
            AgentMemoryStreamingBackup.export(f.context, file, password)
            assertTrue(f.store.deleteById("memory-1"))
            AgentMemoryStreamingBackup.restore(f.context, file, password)
            assertNull(f.reopen().findById("memory-1"))
            assertNotNull(f.reopen().findById("memory-2"))
            assertEquals(1, f.reopen().deletionIndex.snapshot().size)
        } finally { file.delete() }
    }

    @Test fun incomingDeletionIsRestoredWithItsRetractionReferences() = fixture { source -> fixture { target ->
        source.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        assertTrue(source.store.deleteById("memory-1"))
        target.store.saveItems(listOf(deletionMemory(1), deletionMemory(2), deletionMemory(3)))
        val file = backup(source)
        try {
            AgentMemoryStreamingBackup.export(source.context, file, password)
            AgentMemoryStreamingBackup.restore(target.context, file, password)
            assertEquals(listOf(deletionMemory(2)), target.reopen().loadItems())
            assertEquals(source.ledger.snapshot(), target.ledger.snapshot())
            assertTrue(target.ledger.pendingRetractionCount() > 0)
        } finally { file.delete() }
    } }

    @Test fun corruptOrTruncatedArchiveCannotChangeLiveMemory() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(7)))
        val file = backup(f)
        try {
            AgentMemoryStreamingBackup.export(f.context, file, password)
            val content = file.readBytes()
            f.store.saveItems(listOf(deletionMemory(8)))
            for (cutoff in listOf(39, content.size - 1)) {
                file.writeBytes(content.copyOf(cutoff))
                assertNotNull(runCatching { AgentMemoryStreamingBackup.restore(f.context, file, password) }.exceptionOrNull())
                assertEquals(listOf(deletionMemory(8)), f.reopen().loadItems())
            }
            file.writeBytes(content.apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() })
            assertNotNull(runCatching { AgentMemoryStreamingBackup.restore(f.context, file, password) }.exceptionOrNull())
            assertEquals(listOf(deletionMemory(8)), f.reopen().loadItems())
            assertTrue(File(f.context.cacheDir, "memory-backup-staging").listFiles().orEmpty().isEmpty())
        } finally { file.delete() }
    }

    @Test fun lateRecordFailureAndDuplicatePositionsCannotReplaceLiveData() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(9)))
        for (sameId in listOf(true, false)) {
            val file = backup(f)
            try {
                StreamingBackupArchive.write(file, password) { writer ->
                    writer.json("memory", "begin", JSONObject().put("schema", 1))
                    for (id in if (sameId) listOf(1, 1) else listOf(1, 2)) {
                        val item = deletionMemory(id)
                        writer.json("memory-row", AgentPersonalMemoryRows.key(item.id), JSONObject().put("position", 0).put("item", AgentMemoryItemCodec.encode(item)))
                    }
                    writer.json("memory", "end", JSONObject().put("rows", 2).put("active", 2).put("deletions", 0))
                }
                assertNotNull(runCatching { AgentMemoryStreamingBackup.restore(f.context, file, password) }.exceptionOrNull())
                assertEquals(listOf(deletionMemory(9)), f.reopen().loadItems())
            } finally { file.delete() }
        }
    }

    @Test fun sourceCommitFailureRollsBackRowsCountersAndIndexes() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        f.store.browse(AgentMemoryBrowseRequest())
        val file = backup(f)
        try {
            AgentMemoryStreamingBackup.export(f.context, file, password)
            f.store.saveItems(listOf(deletionMemory(7)))
            val meta = f.store.database.readString(AgentPersonalMemoryRows.META, "")
            f.sql().use { sql ->
                sql.execSQL("CREATE TRIGGER test_backup_abort BEFORE INSERT ON encrypted_values WHEN NEW.storage_key='personal-memory:v3:metadata' BEGIN SELECT RAISE(ABORT,'test backup abort'); END")
                try { assertNotNull(runCatching { AgentMemoryStreamingBackup.restore(f.context, file, password) }.exceptionOrNull()) }
                finally { sql.execSQL("DROP TRIGGER test_backup_abort") }
            }
            assertEquals(meta, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
            assertEquals(listOf(deletionMemory(7)), f.reopen().loadItems())
            assertEquals(1L, f.store.browse(AgentMemoryBrowseRequest()).counts.active)
        } finally { file.delete() }
    }

    @Test fun deletionLeavingOneConflictCandidateRestoresItAsActive() = fixture { f ->
        val first = deletionMemory(1).copy(key = "same", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "group")
        val second = deletionMemory(2).copy(key = "same", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "group")
        f.store.saveItems(listOf(first, second))
        val file = backup(f)
        try {
            AgentMemoryStreamingBackup.export(f.context, file, password)
            // Only ID suppression here; a semantic deletion intentionally suppresses both older candidates.
            val record = AgentMemoryCausalDeletionPolicy.tombstone(listOf(first.copy(key = "unrelated")))!!
            f.ledger.mergeBackup(org.json.JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(record)))
            AgentMemoryStreamingBackup.restore(f.context, file, password)
            assertEquals(listOf(second.copy(status = AgentMemoryStatus.ACTIVE, conflictGroupId = "")), f.reopen().loadItems())
        } finally { file.delete() }
    }

    @Test fun tenThousandRealRowsExportAndRestoreWithExactCounts() = fixture { f ->
        Log.i("GalaxySSIMemoryBackupTest", "rows=10001 phase=seed-start")
        f.store.saveItems((0 until 10_001).map { deletionMemory(it) })
        Log.i("GalaxySSIMemoryBackupTest", "rows=10001 phase=seed-complete")
        val file = backup(f)
        try {
            val started = SystemClock.elapsedRealtime()
            assertEquals(10_003L, AgentMemoryStreamingBackup.export(f.context, file, password))
            val exported = SystemClock.elapsedRealtime()
            Log.i("GalaxySSIMemoryBackupTest", "rows=10001 phase=export-complete ms=${exported - started}")
            f.store.saveItems(emptyList())
            Log.i("GalaxySSIMemoryBackupTest", "rows=10001 phase=restore-start")
            AgentMemoryStreamingBackup.restore(f.context, file, password)
            val restored = SystemClock.elapsedRealtime()
            Log.i("GalaxySSIMemoryBackupTest", "rows=10001 phase=restore-complete ms=${restored - exported}")
            assertEquals(10_001, f.reopen().count())
            assertEquals(10_001, f.store.database.countKeys(AgentPersonalMemoryRows.PREFIX))
            var checked = 0L
            AgentPersonalMemoryRows(f.store.database).exportRows { _, row ->
                val item = AgentMemoryItemCodec.decode(row.getJSONObject("item"))!!
                val number = item.id.removePrefix("memory-").toInt()
                assertTrue(number in 0..10_000)
                assertEquals(deletionMemory(number), item)
                assertEquals(number.toLong(), row.getLong("position"))
                checked++
            }
            assertEquals(10_001L, checked)
            Log.i("GalaxySSIMemoryBackupTest", "rows=10001 exportMs=${exported - started} restoreIncludingClearMs=${restored - exported} bytes=${file.length()}")
        } finally { file.delete() }
    }
}
