package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryPartitionsDeviceTest {
    private class Fixture : Closeable {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-knowledge-primary-${UUID.randomUUID()}.db"
        val file = context.getDatabasePath(name)
        val root = File(file.absolutePath + ".primary")
        val db = KnowledgeSqlite(file.absolutePath)
        val parts = KnowledgePrimaryPartitions(context, root, name, partitionRecords = 4)
        init {
            db.execSQL("PRAGMA foreign_keys=ON"); db.execSQL("PRAGMA journal_mode=WAL")
            db.execSQL("PRAGMA synchronous=FULL")
            db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY)")
            KnowledgePrimarySchema.create(db)
        }
        fun key(i: Int) = i.toString(16).padStart(2, '0') + "0".repeat(62)
        fun put(i: Int, value: String) {
            val key = key(i)
            db.delete("knowledge_items", "item_key=?", arrayOf(key))
            db.insertOrThrow("knowledge_items", null, ContentValues().apply { put("item_key", key) })
            parts.append(db, key, value)
        }
        fun transaction(commit: Boolean = true, block: () -> Unit) {
            db.beginTransaction(); parts.begin()
            try { block(); if (commit) { parts.prepareCommit(); db.setTransactionSuccessful() } }
            finally { try { db.endTransaction() } finally { parts.end() } }
        }
        override fun close() { parts.close(); db.close(); println("KNOWLEDGE_PRIMARY_FIXTURE $name") }
    }

    @Test fun authoritativeBodiesRotateAcrossPhysicalPartitionsAndReopen() = Fixture().use { f ->
        f.transaction { repeat(40) { f.put(it, "\u539f\u59cb\u8bb0\u5fc6-$it " + "\ud83d\ude80".repeat(9000)) } }
        val partitions = f.db.rawQuery("SELECT count(*) FROM knowledge_primary_partitions", null).use {
            check(it.moveToFirst()); it.getLong(0)
        }
        assertTrue(partitions > 4)
        assertEquals(partitions, f.root.listFiles()!!.count { it.extension == "sqlite" }.toLong())
        KnowledgePrimaryPartitions(f.context, f.root, f.name).use { reopened ->
            repeat(40) { assertEquals("\u539f\u59cb\u8bb0\u5fc6-$it " + "\ud83d\ude80".repeat(9000), reopened.read(f.db, f.key(it))) }
        }
        f.root.listFiles()!!.filter { it.extension == "sqlite" }.forEach {
            assertFalse(it.readBytes().toString(Charsets.UTF_8).contains("\u539f\u59cb\u8bb0\u5fc6"))
        }
    }

    @Test fun committedFramesCannotEscapeAnUncommittedCatalog() = Fixture().use { f ->
        f.transaction { f.put(1, "before") }
        f.transaction(commit = false) { f.put(1, "after"); f.parts.prepareCommit() }
        assertEquals("before", f.parts.read(f.db, f.key(1)))
        KnowledgePrimaryPartitions(f.context, f.root, f.name).use { reopened ->
            assertEquals("before", reopened.read(f.db, f.key(1)))
        }
    }

    @Test fun pinnedCatalogRetainsOldImmutableRecordAfterReplacement() = Fixture().use { f ->
        f.transaction { f.put(1, "before") }
        KnowledgeSqlite(f.file.absolutePath).use { read ->
            read.execSQL("PRAGMA query_only=ON"); read.execSQL("BEGIN")
            assertEquals("before", f.parts.read(read, f.key(1)))
            f.transaction { f.put(1, "after") }
            assertEquals("before", f.parts.read(read, f.key(1)))
            assertEquals("after", f.parts.read(f.db, f.key(1)))
            read.execSQL("ROLLBACK")
        }
    }

    @Test fun failedAppendPoisonsPublicationEvenWhenCallerCatchesIt() = Fixture().use { f ->
        f.transaction { f.put(1, "before") }
        f.transaction(commit = false) {
            f.put(1, "after")
            assertThrows(IllegalArgumentException::class.java) { f.parts.append(f.db, "invalid key", "body") }
            assertThrows(IllegalStateException::class.java) { f.parts.prepareCommit() }
        }
        assertEquals("before", f.parts.read(f.db, f.key(1)))
    }

    @Test fun swappedReferenceCannotAuthenticateAsAnotherRecord() = Fixture().use { f ->
        f.transaction { f.put(1, "first"); f.put(2, "second") }
        f.db.rawQuery("UPDATE knowledge_primary_refs SET reference=(SELECT reference FROM knowledge_primary_refs WHERE item_key=?) WHERE item_key=?",
            arrayOf(f.key(1), f.key(2))).use { it.moveToNext() }
        assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(2)) }
        assertEquals("first", f.parts.read(f.db, f.key(1)))
    }

    @Test fun corruptOrMissingFramesNeverBecomeAnEmptyResult() = Fixture().use { f ->
        f.transaction { f.put(1, "body") }
        val partition = f.db.rawQuery("SELECT partition_key FROM knowledge_primary_refs WHERE item_key=?", arrayOf(f.key(1))).use {
            check(it.moveToFirst()); it.getString(0)
        }
        KnowledgeSqlite(File(f.root, "$partition.sqlite").absolutePath).use { it.execSQL("DELETE FROM frames") }
        assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(1)) }
        Unit
    }

    @Test fun gzipBombAndInvalidUtf8AreRejectedWithinOneFrame() {
        val output = java.io.ByteArrayOutputStream()
        java.util.zip.GZIPOutputStream(output).use { it.write(ByteArray(80_000) { 65 }) }
        val bomb = android.util.Base64.encodeToString(output.toByteArray(), android.util.Base64.NO_WRAP)
        assertThrows(IllegalArgumentException::class.java) { KnowledgePrimaryFrameCodec.decompress(bomb) }
        val malformed = java.io.ByteArrayOutputStream()
        java.util.zip.GZIPOutputStream(malformed).use { it.write(byteArrayOf(0xc3.toByte(), 0x28)) }
        assertThrows(Exception::class.java) { KnowledgePrimaryFrameCodec.decompress(
            android.util.Base64.encodeToString(malformed.toByteArray(), android.util.Base64.NO_WRAP)) }
    }
}
