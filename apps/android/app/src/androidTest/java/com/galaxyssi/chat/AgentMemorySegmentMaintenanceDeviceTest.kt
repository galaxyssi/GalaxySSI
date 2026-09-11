package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AgentMemorySegmentMaintenanceDeviceTest {
    private fun fixture(test: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { f.store.database.contains("fixture-probe"); test(f) } finally {
            f.clear()
            repeat(8) { f.store.database.maintainMemorySegments(32, 32) }
            val root = root(f)
            check(root.name.startsWith("test-memory-ledger-") && root.name.endsWith(".db.segments"))
            check(!root.exists() || root.deleteRecursively())
        }
    }
    private fun root(f: MemoryDeletionDeviceFixture) = File(f.store.database.storageIdentity + ".segments")
    private fun text(i: Int) = "memory-$i \u6d4b\u8bd5\u6587\u672c ".repeat(900).trim()
    private fun key(i: Int) = AgentPersonalMemoryRows.key("fixture-$i")
    private fun files(f: MemoryDeletionDeviceFixture) = root(f).walkTopDown().filter { it.extension == "seg" }.toList()
    private fun pointer(f: MemoryDeletionDeviceFixture, k: String) = f.sql().use { db ->
        db.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?", arrayOf(k)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }

    @Test fun deletedPayloadIsReclaimedWithoutScanningOrDeletingOtherValues() = fixture { f ->
        val db = f.store.database
        db.writeString(key(1), text(1))
        assertEquals(1, files(f).size)
        db.remove(key(1))
        db.writeString("unrelated", "keep")
        val result = db.maintainMemorySegments()
        assertEquals(1, result.removed)
        assertTrue(result.reclaimedBytes > 0)
        assertTrue(files(f).isEmpty())
        assertEquals("keep", db.readString("unrelated", ""))
        db.writeString(key(2), text(2))
        assertEquals(text(2), db.readString(key(2), ""))
    }

    @Test fun failedPublicationLeavesAnOrphanThatIsDiscoverableAfterReopen() = fixture { f ->
        val db = f.store.database
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER segment_abort BEFORE INSERT ON encrypted_values BEGIN SELECT RAISE(ABORT,'injected'); END")
            try { assertTrue(runCatching { db.writeString(key(1), text(1)) }.isFailure) }
            finally { sql.execSQL("DROP TRIGGER segment_abort") }
        }
        assertFalse(db.contains(key(1)))
        assertEquals(1, files(f).size)
        val reopened = AgentEncryptedDatabase(f.context, AgentMemoryStorage.DATABASE)
        assertEquals(1, reopened.maintainMemorySegments().removed)
        assertTrue(files(f).isEmpty())
    }

    @Test fun compactionMovesAtMostTheRequestedRowsAndPreservesEveryValue() = fixture { f ->
        val db = f.store.database
        repeat(8) { db.writeString(key(it), text(it)) }
        repeat(6) { db.remove(key(it)) }
        val before = pointer(f, key(6))
        val first = db.maintainMemorySegments(1, 1)
        assertEquals(1, first.moved)
        assertEquals(0, first.removed)
        repeat(6) { db.maintainMemorySegments(1, 1) }
        assertNotEquals(before, pointer(f, key(6)))
        assertEquals(text(6), db.readString(key(6), ""))
        assertEquals(text(7), db.readString(key(7), ""))
        assertEquals(2, db.countKeys(AgentPersonalMemoryRows.PREFIX))
    }

    @Test fun interruptedCompactionKeepsOriginalReferencesAndRecoversOrphans() = fixture { f ->
        val db = f.store.database
        repeat(8) { db.writeString(key(it), text(it)) }
        repeat(7) { db.remove(key(it)) }
        val before = pointer(f, key(7))
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER compact_abort BEFORE UPDATE ON encrypted_values BEGIN SELECT RAISE(ABORT,'injected'); END")
            try { assertTrue(runCatching { db.maintainMemorySegments() }.isFailure) }
            finally { sql.execSQL("DROP TRIGGER compact_abort") }
        }
        assertEquals(before, pointer(f, key(7)))
        assertEquals(text(7), db.readString(key(7), ""))
        repeat(6) { db.maintainMemorySegments(1, 1) }
        assertEquals(text(7), db.readString(key(7), ""))
        assertEquals(1, files(f).size)
    }

    @Test fun damagedPayloadAbortsCompactionWithoutDeletingTheSource() = fixture { f ->
        val db = f.store.database
        repeat(8) { db.writeString(key(it), text(it)) }
        repeat(7) { db.remove(key(it)) }
        val before = pointer(f, key(7))
        val segment = files(f).single()
        java.io.RandomAccessFile(segment, "rw").use { it.setLength(it.length() - 1) }
        assertTrue(runCatching { db.maintainMemorySegments() }.isFailure)
        assertEquals(before, pointer(f, key(7)))
        assertTrue(segment.exists())
        assertTrue(runCatching { db.readString(key(7), "fallback") }.isFailure)
    }

    @Test fun corruptInlineEnvelopeIsNotSilentlyReadAsMissingPersonalMemory() = fixture { f ->
        val db = f.store.database
        db.writeString(key(1), "small")
        f.sql().use { it.execSQL("UPDATE encrypted_values SET encrypted_value='broken' WHERE storage_key=?", arrayOf(key(1))) }
        assertTrue(runCatching { db.readString(key(1), "fallback") }.isFailure)
    }

    @Test fun maintenanceCannotRunInsideAnIndexedApplicationTransaction() = fixture { f ->
        assertTrue(runCatching { f.store.database.indexedTransaction { f.store.database.maintainMemorySegments() } }.isFailure)
        f.store.database.writeString(key(1), text(1))
        assertEquals(text(1), f.store.database.readString(key(1), ""))
    }

    @Test fun versionOneUpgradePreservesTheOriginalCiphertext() {
        val f = MemoryDeletionDeviceFixture()
        val path = f.context.getDatabasePath("${AgentMemoryStorage.DATABASE}.db")
        val key = key(42)
        val cipher = AgentStorageCipher.encrypt("original inline memory", "database:${AgentMemoryStorage.DATABASE}:$key".toByteArray())
        try {
            android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(path, null).use {
                it.execSQL("CREATE TABLE encrypted_values(storage_key TEXT PRIMARY KEY NOT NULL, encrypted_value TEXT NOT NULL)")
                it.execSQL("INSERT INTO encrypted_values VALUES(?,?)", arrayOf(key, cipher))
                it.version = 1
            }
            assertEquals("original inline memory", f.store.database.readString(key, ""))
            assertEquals(cipher, pointer(f, key))
            f.sql().use { assertEquals(2, it.version) }
            f.store.database.writeString(key, text(42))
            assertEquals(text(42), f.store.database.readString(key, ""))
        } finally { f.clear(); f.store.database.maintainMemorySegments(32, 32) }
    }

    @Test fun unrelatedDatabasesKeepTheirVersionOneSchema() = fixture { f ->
        val name = "unrelated-segment-fixture"
        val db = AgentEncryptedDatabase(f.context, name)
        try {
            db.writeString("other", text(42))
            assertEquals(text(42), db.readString("other", ""))
            android.database.sqlite.SQLiteDatabase.openDatabase(f.context.getDatabasePath("$name.db").absolutePath, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { sql ->
                assertEquals(1, sql.version)
                sql.rawQuery("PRAGMA table_info(encrypted_values)", null).use { assertEquals(2, it.count) }
            }
        } finally { db.clear() }
    }
}
