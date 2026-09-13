package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryDurabilityDeviceTest {
    private fun assertExtra(db: KnowledgeSqlite) {
        db.rawQuery("PRAGMA synchronous", null).use { assertTrue(it.moveToFirst()); assertEquals(3, it.getInt(0)) }
        db.rawQuery("PRAGMA journal_mode", null).use { assertTrue(it.moveToFirst()); assertEquals("delete", it.getString(0)) }
    }
    private fun scratch() = InstrumentationRegistry.getInstrumentation().targetContext
        .getDatabasePath("test-primary-durability-${UUID.randomUUID()}.db")

    // Inspect the actual live writer connections without adding a production diagnostics interface.
    @Suppress("UNCHECKED_CAST")
    private fun assertWriters(f: KnowledgePrimaryCompactionFixture) {
        val field = KnowledgePrimaryPartitions::class.java.getDeclaredField("writers").apply { isAccessible = true }
        val writers = field.get(f.parts) as Map<String, KnowledgeSqlite>
        assertTrue(writers.isNotEmpty()); writers.values.forEach(::assertExtra)
    }

    @Test fun bundledDriverAppliesAndReportsExtra() {
        val path = scratch()
        KnowledgeSqlite(path.absolutePath).use { db ->
            db.execSQL("PRAGMA synchronous=OFF")
            KnowledgePrimaryDurability.configureWriter(db); assertExtra(db)
            db.execSQL("CREATE TABLE sample(value TEXT)")
            db.beginTransaction()
            try { db.execSQL("INSERT INTO sample VALUES('verified')"); db.setTransactionSuccessful() }
            finally { db.endTransaction() }
        }
        KnowledgeSqlite(path.absolutePath).use { db ->
            KnowledgePrimaryDurability.configureWriter(db); assertExtra(db)
            db.rawQuery("SELECT value FROM sample", null).use { assertTrue(it.moveToFirst()); assertEquals("verified", it.getString(0)) }
        }
    }

    @Test fun unexpectedWalFileIsRejectedRatherThanReconfigured() = KnowledgeSqlite(scratch().absolutePath).use { db ->
        db.execSQL("PRAGMA journal_mode=WAL")
        assertThrows(IllegalStateException::class.java) { KnowledgePrimaryDurability.configureWriter(db) }
        db.rawQuery("PRAGMA journal_mode", null).use { assertTrue(it.moveToFirst()); assertEquals("wal", it.getString(0)) }
    }

    @Test fun configurationMustHappenBeforeStartingAWritingTransaction(): Unit = KnowledgeSqlite(scratch().absolutePath).use { db ->
        db.execSQL("CREATE TABLE sample(value TEXT)"); db.beginTransaction()
        try { assertThrows(Exception::class.java) { KnowledgePrimaryDurability.configureWriter(db) } }
        finally { db.endTransaction() }
    }

    @Test fun newAndReopenedProductionWritersUseExtra() {
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.transaction { f.put(1); assertWriters(f) }; f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            f.transaction { f.put(2); assertWriters(f) }
            assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
            assertEquals("\u8bb0\u5fc6-2", f.parts.read(f.db, f.key(2)))
        }
    }

    @Test fun rotationAndEarlyFlushKeepEveryWriterAtExtra() = KnowledgePrimaryCompactionFixture(records = 2).use { f ->
        f.transaction { repeat(24) { f.put(it); assertWriters(f) } }
        assertEquals(12L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
        repeat(24) { assertEquals("\u8bb0\u5fc6-$it", f.parts.read(f.db, f.key(it))) }
    }

    @Test fun allocationJournalUsesExtraForInsertionAndAcknowledgementConnections() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }
        val method = KnowledgePrimaryAllocations::class.java.getDeclaredMethod("open").apply { isAccessible = true }
        (method.invoke(f.parts.allocations) as KnowledgeSqlite).use(::assertExtra)
        f.drain()
        (method.invoke(f.parts.allocations) as KnowledgeSqlite).use { db ->
            assertExtra(db); db.rawQuery("SELECT count(*) FROM pending", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
    }

    @Test fun incompatibleExistingBodyModeFailsCatalogPublicationWithoutDroppingTheOldRecord() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; val file = File(f.root, "${f.source(1)}.sqlite")
        KnowledgeSqlite(file.absolutePath).use { it.execSQL("PRAGMA journal_mode=WAL") }
        assertThrows(IllegalStateException::class.java) { f.transaction { f.put(2) } }
        assertEquals(1L, f.number("SELECT count(*) FROM knowledge_items"))
        KnowledgeSqlite(file.absolutePath).use { it.execSQL("PRAGMA journal_mode=DELETE") }
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
        assertNull(f.parts.read(f.db, f.key(2)))
    }
}
