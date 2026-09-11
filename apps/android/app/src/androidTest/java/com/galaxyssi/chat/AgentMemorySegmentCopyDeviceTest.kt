package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile

internal fun memoryCopyFixtureValue(): String {
    val random = java.util.Random(301)
    return buildString { repeat(1_700_000) { append(('!'.code + random.nextInt(90)).toChar()) } }
}

@RunWith(AndroidJUnit4::class)
class AgentMemorySegmentCopyDeviceTest {
    private val key = AgentPersonalMemoryRows.key("copy-current")
    private val scope get() = "database:${AgentMemoryStorage.DATABASE}:$key".toByteArray()
    private fun segments(f: MemoryDeletionDeviceFixture) = AgentMemoryPayloadSegments(File(f.store.database.storageIdentity + ".segments"))
    private fun catalogSql(f: MemoryDeletionDeviceFixture) = SQLiteDatabase.openDatabase(
        f.store.database.storageIdentity + ".segments.catalog.db", null, SQLiteDatabase.OPEN_READWRITE)
    private fun files(f: MemoryDeletionDeviceFixture) = File(f.store.database.storageIdentity + ".segments")
        .walkTopDown().filter { it.extension == "seg" }.toList()
    private fun destination(f: MemoryDeletionDeviceFixture, state: MemorySegmentCopy.State) =
        files(f).single { it.name == "${state.destination}.seg" }
    private fun pointer(f: MemoryDeletionDeviceFixture) = f.sql().use { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=?", arrayOf(key)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }
    private fun state(f: MemoryDeletionDeviceFixture): MemorySegmentCopy.State {
        val s = segments(f)
        return s.copyState(requireNotNull(s.catalog.copyJob()), scope)
    }
    private fun fixture(block: (MemoryDeletionDeviceFixture, String) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try {
            val value = memoryCopyFixtureValue()
            f.store.database.writeString(key, value)
            repeat(2) {
                val dead = AgentPersonalMemoryRows.key("copy-dead-$it")
                f.store.database.writeString(dead, value)
                f.store.database.remove(dead)
            }
            f.store.database.maintainMemorySegments(1, 1)
            assertTrue(state(f).source.length > 1024 * 1024)
            block(f, value)
        } finally {
            f.clear()
            repeat(20) { f.store.database.maintainMemorySegments(32, 32) }
        }
    }
    private fun finish(f: MemoryDeletionDeviceFixture) {
        repeat(20) { f.store.database.maintainMemorySegments(32, 32) }
        assertNull(segments(f).catalog.copyJob())
    }

    @Test fun multipleBatchesPreserveTheOriginalUntilDestinationVerificationCompletes() = fixture { f, value ->
        val before = pointer(f)
        val db = AgentEncryptedDatabase(f.context, AgentMemoryStorage.DATABASE)
        do {
            val old = state(f)
            db.maintainMemorySegments(1, 1)
            val next = state(f)
            assertTrue(next.copiedBytes - old.copiedBytes <= 1024 * 1024)
            assertEquals(before, pointer(f))
        } while (state(f).copiedBytes < state(f).source.length)
        assertEquals(0L, state(f).verifiedBytes)
        finish(f)
        assertNotEquals(before, pointer(f))
        assertTrue("Large memory round trip mismatch", value == db.readString(key, ""))
        assertEquals(1, files(f).size)
    }

    @Test fun updatedSourceSupersedesThePendingCopyAndNeverResurrectsOldContent() = fixture { f, _ ->
        f.store.database.maintainMemorySegments(1, 1)
        f.store.database.writeString(key, "new user content")
        finish(f)
        assertEquals("new user content", f.store.database.readString(key, ""))
        assertTrue(files(f).isEmpty())
    }

    @Test fun deletionDuringCopyRemainsDeletedAfterCleanup() = fixture { f, _ ->
        f.store.database.maintainMemorySegments(1, 1)
        f.store.database.remove(key)
        finish(f)
        assertFalse(f.store.database.contains(key))
        assertTrue(files(f).isEmpty())
    }

    @Test fun failedCheckpointAfterFileSyncReplaysOnlyUnpublishedBytes() = fixture { f, value ->
        val before = pointer(f)
        catalogSql(f).use { sql ->
            sql.execSQL("CREATE TRIGGER checkpoint_abort BEFORE UPDATE ON copy_job BEGIN SELECT RAISE(ABORT,'checkpoint abort'); END")
            try { assertTrue(runCatching { f.store.database.maintainMemorySegments(1, 1) }.isFailure) }
            finally { sql.execSQL("DROP TRIGGER checkpoint_abort") }
        }
        assertEquals(0L, state(f).copiedBytes)
        assertTrue(destination(f, state(f)).length() > 0)
        assertEquals(before, pointer(f))
        finish(f)
        assertTrue("Large memory round trip mismatch", value == f.store.database.readString(key, ""))
    }

    @Test fun corruptedDestinationCannotReplaceAReadableOriginal() = fixture { f, value ->
        while (state(f).copiedBytes < state(f).source.length) f.store.database.maintainMemorySegments(1, 1)
        val before = pointer(f)
        RandomAccessFile(destination(f, state(f)), "rw").use {
            it.seek(8); val byte = it.readUnsignedByte(); it.seek(8); it.writeByte(byte xor 1)
        }
        assertTrue(runCatching { f.store.database.maintainMemorySegments(1, 1) }.isFailure)
        assertEquals(before, pointer(f))
        assertNotNull(segments(f).catalog.copyJob())
        assertTrue("Original memory changed after destination corruption", value == f.store.database.readString(key, ""))
    }

    @Test fun failedJobCleanupAfterCommitDoesNotPublishTheReferenceTwice() = fixture { f, value ->
        val before = pointer(f)
        catalogSql(f).use { sql ->
            sql.execSQL("CREATE TRIGGER cleanup_abort BEFORE DELETE ON copy_job BEGIN SELECT RAISE(ABORT,'cleanup abort'); END")
            try {
                assertTrue(runCatching { repeat(20) { f.store.database.maintainMemorySegments(1, 1) } }.isFailure)
            } finally { sql.execSQL("DROP TRIGGER cleanup_abort") }
        }
        assertTrue(state(f).complete)
        val published = pointer(f)
        assertNotEquals(before, published)
        finish(f)
        assertEquals(published, pointer(f))
        assertTrue("Published memory changed", value == f.store.database.readString(key, ""))
        assertEquals(1, files(f).size)
    }

    @Test fun damagedCheckpointAndWrongScopeDoNotAllowReclamation() = fixture { f, value ->
        val s = segments(f)
        val job = requireNotNull(s.catalog.copyJob())
        assertTrue(runCatching { s.copyState(job, "different scope".toByteArray()) }.isFailure)
        catalogSql(f).use { sql ->
            sql.execSQL("UPDATE copy_job SET checkpoint='broken' WHERE id=1")
            try {
                assertTrue(runCatching { f.store.database.maintainMemorySegments(1, 1) }.isFailure)
                assertEquals(2, files(f).size)
                assertTrue("Original memory changed after checkpoint corruption", value == f.store.database.readString(key, ""))
            } finally { sql.execSQL("UPDATE copy_job SET checkpoint=? WHERE id=1", arrayOf(job.checkpoint)) }
        }
    }

    @Test fun missingVerifiedDestinationKeepsTheOriginalReference() = fixture { f, value ->
        val before = pointer(f)
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER publication_abort BEFORE UPDATE ON encrypted_values BEGIN SELECT RAISE(ABORT,'publication abort'); END")
            try {
                assertTrue(runCatching { repeat(20) { f.store.database.maintainMemorySegments(1, 1) } }.isFailure)
            } finally { sql.execSQL("DROP TRIGGER publication_abort") }
        }
        assertTrue(state(f).complete)
        assertTrue(destination(f, state(f)).delete())
        assertTrue(runCatching { f.store.database.maintainMemorySegments(1, 1) }.isFailure)
        assertEquals(before, pointer(f))
        assertTrue("Original memory changed after missing destination", value == f.store.database.readString(key, ""))
    }
}
