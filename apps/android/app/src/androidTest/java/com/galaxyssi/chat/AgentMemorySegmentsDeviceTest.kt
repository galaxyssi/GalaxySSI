package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile

@RunWith(AndroidJUnit4::class)
class AgentMemorySegmentsDeviceTest {
    private fun root(f: MemoryDeletionDeviceFixture) = File(
        f.context.getDatabasePath("${AgentMemoryStorage.DATABASE}.db").absolutePath + ".segments")
    private fun fixture(test: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { test(f) } finally {
            f.clear()
            val root = root(f)
            check(root.name.startsWith("test-memory-ledger-") && root.name.endsWith(".db.segments"))
            check(!root.exists() || root.deleteRecursively())
        }
    }
    private fun longValue() = "\u79c1\u5bc6\u8bb0\u5fc6-\ud83d\ude80-indexed archive payload. ".repeat(1_000).trim()
    private fun pointer(f: MemoryDeletionDeviceFixture, key: String) = f.sql().use { db ->
        db.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?", arrayOf(key)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }
    private fun fails(block: () -> Unit) { assertNotNull(runCatching(block).exceptionOrNull()) }

    @Test fun largeRowsAreCompressedEncryptedAndResolvedByTheProductionStore() = fixture { f ->
        val value = longValue()
        f.store.saveItems(listOf(deletionMemory(1, value)))
        val raw = pointer(f, AgentPersonalMemoryRows.key("memory-1"))
        assertTrue(raw.startsWith(AgentMemoryPayloadSegments.PREFIX))
        assertTrue(raw.length < 256)
        assertEquals(value, f.reopen().loadItems().single().value)
        val segments = root(f).walkTopDown().filter { it.isFile }.toList()
        assertTrue(segments.isNotEmpty())
        assertTrue(segments.sumOf(File::length) < value.toByteArray().size / 2)
        segments.forEach { assertFalse(it.readBytes().toString(Charsets.ISO_8859_1).contains("indexed archive payload")) }
    }

    @Test fun smallRowsAndUnrelatedDatabaseValuesStayInline() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        assertTrue(pointer(f, AgentPersonalMemoryRows.key("memory-1")).startsWith("enc:v1:"))
        f.store.database.writeString("other-component", longValue())
        assertTrue(pointer(f, "other-component").startsWith("enc:v1:"))
        assertFalse(root(f).exists())
    }

    @Test fun explicitLargeStoreWritesSmallRowsExternallyWithoutAWholeStoreCopy() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1), deletionMemory(2)))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val value = f.store.database.readString(key, "")
        val other = pointer(f, AgentPersonalMemoryRows.key("memory-2"))
        f.store.database.mutateStrings(mapOf(key to value), segmentPersonalRows = true)
        assertTrue(pointer(f, key).startsWith(AgentMemoryPayloadSegments.PREFIX))
        assertEquals(value, f.store.database.readString(key, ""))
        assertEquals(other, pointer(f, AgentPersonalMemoryRows.key("memory-2")))
        assertEquals(2, f.reopen().count())
    }

    @Test fun failedSqlPublicationKeepsThePreviousReferenceAndIndexedState() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, longValue())))
        val key = AgentPersonalMemoryRows.key("memory-1")
        val before = pointer(f, key)
        f.sql().use { db ->
            db.execSQL("CREATE TRIGGER test_segment_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key='${AgentPersonalMemoryRows.META}' BEGIN SELECT RAISE(ABORT,'injected'); END")
            try { fails { f.store.setImportant("memory-1", true) } }
            finally { db.execSQL("DROP TRIGGER test_segment_abort") }
        }
        assertEquals(before, pointer(f, key))
        assertFalse(f.reopen().loadItems().single().important)
        assertTrue(f.store.setImportant("memory-1", true))
        assertTrue(f.reopen().loadItems().single().important)
    }

    @Test fun pointerCannotBeCopiedToAnotherMemoryIdentity() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, longValue()), deletionMemory(2, longValue())))
        val one = pointer(f, AgentPersonalMemoryRows.key("memory-1"))
        f.sql().use { it.execSQL("UPDATE encrypted_values SET encrypted_value=? WHERE storage_key=?",
            arrayOf(one, AgentPersonalMemoryRows.key("memory-2"))) }
        fails { f.store.database.readString(AgentPersonalMemoryRows.key("memory-2"), "must-not-return-default") }
    }

    @Test fun lostOrCorruptSegmentFailsExplicitlyInsteadOfReturningDefault() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1, longValue())))
        val segment = root(f).walkTopDown().single { it.isFile }
        RandomAccessFile(segment, "rw").use {
            it.seek(10); val old = it.readUnsignedByte(); it.seek(10); it.write(old xor 1)
        }
        fails { f.reopen().loadItems() }
        assertTrue(segment.delete())
        fails { f.store.database.readString(AgentPersonalMemoryRows.key("memory-1"), "fallback") }
    }

    @Test fun segmentedAndInlineRowsShareNormalUpdateDeleteAndBrowseSemantics() = fixture { f ->
        val items = listOf(deletionMemory(1, longValue()), deletionMemory(2), deletionMemory(3, longValue()))
        f.store.saveItems(items)
        assertEquals(items, f.reopen().loadItems())
        assertEquals(3L, AgentPersonalMemoryRows(f.store.database).browse(AgentMemoryBrowseRequest()).counts.active)
        assertTrue(f.store.setPrivate("memory-1", true))
        assertTrue(f.store.setImportant("memory-3", true))
        assertTrue(f.store.deleteById("memory-1"))
        assertEquals(listOf("memory-2", "memory-3"), f.reopen().loadItems().map { it.id })
        assertEquals(2, f.reopen().count())
        val page = AgentPersonalMemoryRows(f.store.database).browse(AgentMemoryBrowseRequest())
        assertEquals(listOf("memory-3", "memory-2"), page.entries.map { it.item.id })
        assertEquals(2L, page.counts.active)
        assertEquals(listOf("memory-3"), f.store.recall("indexed archive payload").map { it.id })
    }

    @Test fun streamingBackupRestoresExternalPayloadsAndRespectsLaterDeletion() = fixture { f ->
        val before = listOf(deletionMemory(1, longValue()), deletionMemory(2, longValue()))
        f.store.saveItems(before)
        val archive = File(f.context.cacheDir, "segment-roundtrip.hcbak")
        val password = "synthetic-segment-password".toCharArray()
        try {
            AgentMemoryStreamingBackup.export(f.context, archive, password)
            f.store.saveItems(listOf(deletionMemory(999)))
            AgentMemoryStreamingBackup.restore(f.context, archive, password)
            assertEquals(before, f.reopen().loadItems())
            assertTrue(f.store.deleteById("memory-1"))
            AgentMemoryStreamingBackup.restore(f.context, archive, password)
            assertNull(f.reopen().findById("memory-1"))
            assertEquals(before[1], f.reopen().findById("memory-2"))
        } finally { password.fill('\u0000'); archive.delete() }
    }

    @Test fun payloadSelectionHasNoCountBasedDataDeletion() {
        val key = AgentPersonalMemoryRows.key("fixture")
        assertFalse(AgentMemoryPayloadSegments.external(key, "short", false))
        assertTrue(AgentMemoryPayloadSegments.external(key, "short", true))
        assertTrue(AgentMemoryPayloadSegments.external(key, "a".repeat(8_192), false))
        assertFalse(AgentMemoryPayloadSegments.external("unrelated", "a".repeat(9_000), true))
        assertEquals(16_384L, AgentMemoryPayloadSegments.ROW_THRESHOLD)
    }
}
