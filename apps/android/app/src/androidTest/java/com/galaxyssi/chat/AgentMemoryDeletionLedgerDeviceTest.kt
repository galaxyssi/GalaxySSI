package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryDeletionLedgerDeviceTest {
    private fun withFixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val fixture = MemoryDeletionDeviceFixture()
        try { block(fixture) } finally { fixture.clear() }
    }

    private fun tombstone(index: Int) = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deletionMemory(index)), index + 2L)!!
    private fun encoded(items: List<AgentMemoryItem>, fixture: MemoryDeletionDeviceFixture) =
        JSONArray().apply { items.forEach { put(fixture.store.encodeMemoryItem(it)) } }

    @Test fun recordCapacityIsUnboundedAndEarlierRowsRemainRestorationBarriers() = withFixture { fixture ->
        val input = JSONArray().apply { (0 until 2_105).forEach { put(AgentMemoryCausalDeletionPolicy.encode(tombstone(it))) } }
        fixture.ledger.mergeBackup(input)
        assertEquals(2_105, fixture.reopen().deletionIndex.snapshot().size)
        assertEquals(2_105, fixture.store.database.keys(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX).size)
        assertEquals(0, fixture.ledger.filterBackupItems(encoded(listOf(deletionMemory(0), deletionMemory(2_104)), fixture)).length())
        fixture.ledger.record(listOf(deletionMemory(3_000)))
        assertEquals(2_106, fixture.reopen().deletionIndex.snapshot().size)
    }

    @Test fun largeSingleDeletionRetainsEveryIdAndRetraction() = withFixture { fixture ->
        val removed = (0 until 1_501).map { deletionMemory(it, "\u5f85\u5220\u9664-$it") }
        fixture.store.saveItems(removed + deletionMemory(2_000, "\u4fdd\u7559"))
        assertEquals(1_501, fixture.store.delete("\u5f85\u5220\u9664"))
        assertEquals(listOf("memory-2000"), fixture.reopen().snapshot().activeItems.map { it.id })
        val record = fixture.reopen().deletionIndex.snapshot().single()
        assertEquals(removed.map { it.id }.toSet(), record.memoryIds)
        assertTrue(record.retractedEventIds.size > 2_000)
        assertEquals(record, AgentMemoryCausalDeletionPolicy.decode(AgentMemoryCausalDeletionPolicy.encode(record)))
        assertEquals(0, fixture.ledger.filterBackupItems(encoded(removed, fixture)).length())
    }

    @Test fun legacyLargeRecordMigratesWithoutTruncationAndKeepsOriginalEncryptedSource() = withFixture { fixture ->
        val record = AgentMemoryCausalDeletionPolicy.tombstone((0 until 1_501).map { deletionMemory(it) }, 2)!!
        val raw = JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(record)).toString()
        fixture.legacy.writeString("tombstones", raw)
        assertEquals(listOf(record), fixture.ledger.snapshot())
        assertEquals("1", fixture.store.database.readString(EncryptedAgentMemoryDeletionIndex.MIGRATION_KEY, ""))
        assertEquals(raw, fixture.legacy.readString("tombstones", ""))
        fixture.ledger.record(listOf(deletionMemory(2_000)))
        assertEquals(2, fixture.reopen().deletionIndex.snapshot().size)
        assertEquals(raw, fixture.legacy.readString("tombstones", ""))
    }

    @Test fun corruptLegacyLedgerCannotDeleteMemoryOrCommitMigration() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val before = AgentPersonalMemoryRows(fixture.store.database).export().toString()
        fixture.legacy.writeString("tombstones", "corrupt-ledger")
        assertNotNull(runCatching { fixture.store.deleteById("memory-1") }.exceptionOrNull())
        assertEquals(before, AgentPersonalMemoryRows(fixture.store.database).export().toString())
        assertFalse(fixture.store.database.contains(EncryptedAgentMemoryDeletionIndex.MIGRATION_KEY))
        assertEquals(1, fixture.reopen().count())
    }

    @Test fun corruptNewRowBlocksRestoreInsteadOfBecomingAnEmptyLedger() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val record = fixture.ledger.record(listOf(deletionMemory(2)))!!
        fixture.store.database.writeString(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + record.id, "bad-json")
        val before = AgentPersonalMemoryRows(fixture.store.database).export().toString()
        assertNotNull(runCatching { fixture.ledger.snapshot() }.exceptionOrNull())
        assertNotNull(runCatching { fixture.ledger.restoreState(encoded(listOf(deletionMemory(3)), fixture), null) }.exceptionOrNull())
        assertEquals(before, AgentPersonalMemoryRows(fixture.store.database).export().toString())
    }

    @Test fun sqliteWriteFailureRollsBackMemoryAndDeletionRecordTogether() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        fixture.ledger.snapshot()
        val before = AgentPersonalMemoryRows(fixture.store.database).export().toString()
        fixture.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_deletion_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key LIKE 'memory-deletion:v2:record:%' " +
                "BEGIN SELECT RAISE(ABORT, 'test_deletion_abort'); END")
            try {
                assertNotNull(runCatching { fixture.store.deleteById("memory-1") }.exceptionOrNull())
                assertEquals(before, AgentPersonalMemoryRows(fixture.store.database).export().toString())
                assertEquals(2, fixture.reopen().count())
                assertTrue(fixture.ledger.snapshot().isEmpty())
            } finally { sql.execSQL("DROP TRIGGER test_deletion_abort") }
        }
        assertTrue(fixture.store.deleteById("memory-1"))
        assertEquals(listOf("memory-2"), fixture.reopen().snapshot().activeItems.map { it.id })
        assertEquals(setOf("memory-1"), fixture.ledger.snapshot().single().memoryIds)
    }

    @Test fun realBackupExportDoesNotTruncateMemoryCountOrLargeValues() = withFixture { source ->
        withFixture { target ->
            val originals = (0 until 801).map { deletionMemory(it) }.toMutableList()
            originals[0] = originals[0].copy(value = "\u8bb0".repeat(30_001))
            source.store.saveItems(originals)
            val backup = AgentBackupData.export(source.context, includeSessionHistory = false)
            assertEquals(801, backup.getJSONArray("memory").length())
            target.ledger.record(listOf(originals[1]))
            target.ledger.restoreState(backup.getJSONArray("memory"), backup.getJSONArray("memory_deletion_index"))
            val actual = target.reopen().snapshot().activeItems
            assertEquals(originals.filterNot { it.id == "memory-1" }.toSet(), actual.toSet())
            assertEquals(30_001, actual.single { it.id == "memory-0" }.value.length)
        }
    }

    @Test fun invalidIncomingRecordCannotPartiallyRestoreValidPrecedingRows() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val incoming = JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(tombstone(2)))
            .put(JSONObject().put("id", "invalid"))
        assertNotNull(runCatching { fixture.ledger.restoreState(encoded(listOf(deletionMemory(3)), fixture), incoming) }.exceptionOrNull())
        assertEquals(listOf("memory-1"), fixture.reopen().snapshot().activeItems.map { it.id })
        assertTrue(fixture.ledger.snapshot().isEmpty())
    }

    @Test fun concurrentInstancesAppendWithoutLosingEachOthersRecords() = withFixture { fixture ->
        val workers = Executors.newFixedThreadPool(4)
        try {
            val jobs = (0 until 4).map { worker -> workers.submit {
                val index = EncryptedAgentMemoryDeletionIndex(fixture.context)
                repeat(20) { index.record(listOf(deletionMemory(worker * 20 + it))) }
            } }
            jobs.forEach { it.get(60, TimeUnit.SECONDS) }
        } finally { workers.shutdownNow() }
        assertEquals((0 until 80).map { "memory-$it" }.toSet(), fixture.ledger.snapshot().flatMap { it.memoryIds }.toSet())
    }

    @Test fun exportSnapshotsDoNotMixPreDeleteItemsWithPostDeleteLedger() = withFixture { fixture ->
        val originals = (0 until 30).map { deletionMemory(it) }
        fixture.store.saveItems(originals)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val job = worker.submit { originals.forEach { fixture.store.deleteById(it.id) } }
            repeat(20) {
                val state = fixture.ledger.exportState()
                val items = state.getJSONArray("memory")
                val live = (0 until items.length()).map { items.getJSONObject(it).getString("id") }.toSet()
                val records = state.getJSONArray("memory_deletion_index")
                val deleted = (0 until records.length()).flatMap {
                    AgentMemoryCausalDeletionPolicy.decode(records.getJSONObject(it))!!.memoryIds
                }.toSet()
                assertTrue(live.intersect(deleted).isEmpty())
                assertEquals(originals.map { it.id }.toSet(), live + deleted)
            }
            job.get(60, TimeUnit.SECONDS)
        } finally { worker.shutdownNow() }
    }

    @Test fun migrationMarkerFailureRollsBackCopiedRowsAndRetainsLegacySource() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val raw = JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(tombstone(2))).toString()
        fixture.legacy.writeString("tombstones", raw)
        fixture.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_migration_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key = 'memory-deletion:v2:migrated' " +
                "BEGIN SELECT RAISE(ABORT, 'test_migration_abort'); END")
            try {
                assertNotNull(runCatching { fixture.ledger.snapshot() }.exceptionOrNull())
                assertFalse(fixture.store.database.contains(EncryptedAgentMemoryDeletionIndex.MIGRATION_KEY))
                assertTrue(fixture.store.database.keys(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX).isEmpty())
                assertEquals(raw, fixture.legacy.readString("tombstones", ""))
                assertEquals(1, fixture.store.count())
            } finally { sql.execSQL("DROP TRIGGER test_migration_abort") }
        }
        assertEquals(listOf(tombstone(2)), fixture.ledger.snapshot())
    }

    @Test fun restorationWriteFailurePreservesBothPreviousDomains() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        fixture.ledger.snapshot()
        val input = encoded(listOf(deletionMemory(2), deletionMemory(3)), fixture)
        val incoming = JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(tombstone(2)))
        fixture.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_restore_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key LIKE 'memory-deletion:v2:record:%' " +
                "BEGIN SELECT RAISE(ABORT, 'test_restore_abort'); END")
            try {
                assertNotNull(runCatching { fixture.ledger.restoreState(input, incoming) }.exceptionOrNull())
                assertEquals(listOf("memory-1"), fixture.reopen().snapshot().activeItems.map { it.id })
                assertTrue(fixture.ledger.snapshot().isEmpty())
            } finally { sql.execSQL("DROP TRIGGER test_restore_abort") }
        }
        fixture.ledger.restoreState(input, incoming)
        assertEquals(listOf("memory-3"), fixture.reopen().snapshot().activeItems.map { it.id })
        assertEquals(listOf(tombstone(2)), fixture.ledger.snapshot())
    }

    @Test fun invalidCiphertextCannotDisableDeletionProtection() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val record = fixture.ledger.record(listOf(deletionMemory(2)))!!
        fixture.sql().use { sql ->
            sql.execSQL("UPDATE encrypted_values SET encrypted_value = ? WHERE storage_key = ?",
                arrayOf("enc:v1:invalid-ciphertext", EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + record.id))
        }
        assertNotNull(runCatching { fixture.ledger.exportState() }.exceptionOrNull())
        assertNotNull(runCatching { fixture.ledger.restoreState(encoded(listOf(deletionMemory(2)), fixture), null) }.exceptionOrNull())
        assertEquals(listOf("memory-1"), fixture.reopen().snapshot().activeItems.map { it.id })
    }

    @Test fun malformedMemoryBackupCannotReplaceHealthyStoredMemory() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val cases = listOf(JSONArray().put(JSONObject().put("id", "empty-value")),
            JSONArray().put(JSONObject().put("value", "\u7f3a\u5c11\u6807\u8bc6")),
            encoded(listOf(deletionMemory(2), deletionMemory(2)), fixture))
        cases.forEach { input ->
            assertNotNull(runCatching { fixture.ledger.restoreState(input, null) }.exceptionOrNull())
            assertEquals(listOf("memory-1"), fixture.reopen().snapshot().activeItems.map { it.id })
        }
    }

    @Test fun malformedTopLevelBackupFieldIsNotTreatedAsMissing() = withFixture { fixture ->
        fixture.store.saveItems(listOf(deletionMemory(1)))
        val cases = listOf(
            JSONObject().put("memory", "not-an-array"),
            JSONObject().put("memory", encoded(listOf(deletionMemory(2)), fixture))
                .put("memory_deletion_index", JSONObject()),
            JSONObject().put("memory_deletion_index", JSONObject.NULL)
        )
        cases.forEach { payload ->
            assertNotNull(runCatching { fixture.ledger.restoreState(payload) }.exceptionOrNull())
            assertEquals(listOf("memory-1"), fixture.reopen().snapshot().activeItems.map { it.id })
            assertTrue(fixture.ledger.snapshot().isEmpty())
        }
        fixture.ledger.restoreState(JSONObject().put("memory_deletion_index",
            JSONArray().put(AgentMemoryCausalDeletionPolicy.encode(tombstone(1)))))
        assertEquals(0, fixture.reopen().count())
        assertEquals(listOf(tombstone(1)), fixture.ledger.snapshot())
    }
}
