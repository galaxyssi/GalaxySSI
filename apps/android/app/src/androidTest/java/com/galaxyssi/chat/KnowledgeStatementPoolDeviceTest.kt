package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeStatementPoolDeviceTest {
    private fun <T> fixture(capacity: Int = 32, block: (KnowledgeSqlite, String) -> T): T {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-statements-${UUID.randomUUID()}.db"
        val path = context.getDatabasePath(name).absolutePath
        try { return KnowledgeSqlite(path, capacity).use { block(it, path) } }
        finally { context.deleteDatabase(name) }
    }
    private fun scalar(db: KnowledgeSqlite, sql: String, args: Array<String>? = null) = db.rawQuery(sql, args).use {
        check(it.moveToFirst()); it.getLong(0)
    }

    @Test fun repeatedQueriesCompileOnceAndKeepResultsIndependent() = fixture { db, _ ->
        repeat(100) { assertEquals(it.toLong(), scalar(db, "SELECT ?", arrayOf(it.toString()))) }
        assertEquals(1L, db.statementStats.prepared)
        assertEquals(99L, db.statementStats.reused)
        assertEquals(1, db.statementStats.idle)
    }

    @Test fun releasedParametersAreNullEvenAfterPartialBinding() = fixture { db, _ ->
        val sql = "SELECT coalesce(?, 'empty'),coalesce(?, 'empty')"
        db.rawQuery(sql, arrayOf("\u79c1\u5bc6\u7ed1\u5b9a", "old-second")).use { assertTrue(it.moveToFirst()) }
        db.rawQuery(sql, arrayOf("new-first")).use {
            assertTrue(it.moveToFirst()); assertEquals("new-first", it.getString(0)); assertEquals("empty", it.getString(1))
        }
        db.rawQuery(sql, null).use {
            assertTrue(it.moveToFirst()); assertEquals("empty", it.getString(0)); assertEquals("empty", it.getString(1))
        }
        assertEquals(1L, db.statementStats.prepared)
    }

    @Test fun concurrentIdenticalCursorsNeverShareTheirStatement() = fixture { db, _ ->
        val sql = "SELECT ? UNION ALL SELECT ?"
        db.rawQuery(sql, arrayOf("first-a", "first-b")).use { first ->
            assertTrue(first.moveToFirst()); assertEquals("first-a", first.getString(0))
            db.rawQuery(sql, arrayOf("second-a", "second-b")).use { second ->
                assertTrue(second.moveToFirst()); assertEquals("second-a", second.getString(0))
                assertTrue(first.moveToNext()); assertEquals("first-b", first.getString(0))
                assertTrue(second.moveToNext()); assertEquals("second-b", second.getString(0))
            }
        }
        assertEquals(2L, db.statementStats.prepared)
        assertEquals(1, db.statementStats.idle)
    }

    @Test fun constraintFailureIsDiscardedAndLaterWritesStillCommit() = fixture { db, _ ->
        db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
        fun insert(id: Long) = db.insertOrThrow("sample", null, ContentValues().apply { put("id", id) })
        insert(1)
        assertThrows(Exception::class.java) { insert(1) }
        insert(2)
        assertEquals(2L, scalar(db, "SELECT count(*) FROM sample"))
    }

    @Test fun nestedRollbackCannotBeChangedByReusedTransactionStatements() = fixture { db, _ ->
        db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
        repeat(3) {
            db.beginTransaction()
            db.beginTransaction()
            db.execSQL("INSERT INTO sample VALUES(1)")
            db.endTransaction()
            db.setTransactionSuccessful(); db.endTransaction()
            assertEquals(0L, scalar(db, "SELECT count(*) FROM sample"))
        }
        db.beginTransaction(); db.execSQL("INSERT INTO sample VALUES(2)")
        db.setTransactionSuccessful(); db.endTransaction()
        assertEquals(2L, scalar(db, "SELECT id FROM sample"))
    }

    @Test fun idleStatementCountAndSqlTextRemainBounded() = fixture(2) { db, _ ->
        repeat(100) { assertEquals(it.toLong(), scalar(db, "SELECT $it")); assertTrue(db.statementStats.idle <= 2) }
        assertTrue(db.statementStats.evicted >= 98)
        val before = db.statementStats
        scalar(db, "SELECT 1 /*" + "x".repeat(64 * 1024) + "*/")
        assertEquals(before.idle, db.statementStats.idle)
        assertEquals(before.sqlChars, db.statementStats.sqlChars)
        assertTrue(db.statementStats.sqlChars <= 64 * 1024)
    }

    @Test fun schemaChangesReprepareCachedQueriesAndRespectNewTriggers() = fixture { db, _ ->
        db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
        db.execSQL("INSERT INTO sample VALUES(1)")
        db.rawQuery("SELECT * FROM sample", null).use { assertTrue(it.moveToFirst()) }
        db.execSQL("ALTER TABLE sample ADD COLUMN label TEXT NOT NULL DEFAULT 'new-schema'")
        db.rawQuery("SELECT * FROM sample", null).use { assertTrue(it.moveToFirst()); assertEquals("new-schema", it.getString(1)) }
        val values = ContentValues().apply { put("id", 2L) }
        db.insertOrThrow("sample", null, values)
        db.execSQL("CREATE TRIGGER reject_sample BEFORE INSERT ON sample BEGIN SELECT RAISE(ABORT,'rejected'); END")
        values.put("id", 3L)
        assertThrows(Exception::class.java) { db.insertOrThrow("sample", null, values) }
        db.execSQL("DROP TRIGGER reject_sample")
        db.insertOrThrow("sample", null, values)
        assertEquals(3L, scalar(db, "SELECT count(*) FROM sample"))
    }

    @Test fun closingConnectionInvalidatesActiveCursorsAndReleasesPool() = fixture { db, _ ->
        val cursor = db.rawQuery("SELECT 1 UNION ALL SELECT 2", null)
        assertTrue(cursor.moveToFirst())
        db.close()
        assertThrows(IllegalStateException::class.java) { cursor.moveToNext() }
        cursor.close()
        assertEquals(0, db.statementStats.idle)
        assertThrows(IllegalStateException::class.java) { db.execSQL("SELECT 1") }
        Unit
    }

    @Test fun returningAnUnfinishedCursorReleasesRollbackJournalReadLocks() = fixture { db, path ->
        db.execSQL("PRAGMA journal_mode=DELETE")
        db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
        db.execSQL("INSERT INTO sample VALUES(1),(2),(3)")
        KnowledgeSqlite(path).use { writer ->
            writer.execSQL("PRAGMA busy_timeout=50")
            db.rawQuery("SELECT id FROM sample ORDER BY id", null).use { assertTrue(it.moveToFirst()) }
            writer.beginTransaction(); writer.execSQL("INSERT INTO sample VALUES(4)")
            writer.setTransactionSuccessful(); writer.endTransaction()
            assertEquals(4L, scalar(db, "SELECT count(*) FROM sample"))
        }
    }

    @Test fun cursorStepFailuresDoNotPoisonTheNextQuery() = fixture { db, _ ->
        repeat(3) {
            assertThrows(Exception::class.java) { db.rawQuery("SELECT abs(-9223372036854775808)", null).use { it.moveToFirst() } }
            assertEquals(42L, scalar(db, "SELECT 42"))
        }
    }

    @Test fun typedBindingsAreOverwrittenAndNullsDoNotReuseOldBlobs() = fixture { db, _ ->
        db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY,payload BLOB,label TEXT)")
        val first = ContentValues().apply { put("id", 1L); put("payload", byteArrayOf(1, 2, 3)); put("label", "first") }
        db.insertOrThrow("sample", null, first)
        val second = ContentValues(first).apply { put("id", 2L); putNull("payload"); putNull("label") }
        db.insertOrThrow("sample", null, second)
        assertEquals(1L, scalar(db, "SELECT payload IS NULL AND label IS NULL FROM sample WHERE id=2"))
        db.rawQuery("SELECT payload FROM sample WHERE id=1", null).use { assertTrue(it.moveToFirst()); assertArrayEquals(byteArrayOf(1, 2, 3), it.getBlob(0)) }
        db.update("sample", ContentValues().apply { put("label", "updated") }, "id=?", arrayOf("1"))
        db.update("sample", ContentValues().apply { putNull("label") }, "id=?", arrayOf("2"))
        assertEquals(1L, scalar(db, "SELECT label IS NULL FROM sample WHERE id=2"))
    }

    @Test fun alternatingCachedAndUncachedTransactionsVerifyTheSameRows() {
        val compilations = mutableListOf<Long>()
        for ((round, capacity) in listOf(0, 32, 32, 0).withIndex()) fixture(capacity) { db, _ ->
            db.execSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY,label TEXT NOT NULL)")
            val started = System.nanoTime()
            db.beginTransaction()
            repeat(512) { id ->
                db.insertOrThrow("sample", null, ContentValues().apply { put("id", id.toLong()); put("label", "\u5206\u7247\u8bfb\u5199-$id") })
                db.rawQuery("SELECT label FROM sample WHERE id=?", arrayOf(id.toString())).use { assertTrue(it.moveToFirst()); assertEquals("\u5206\u7247\u8bfb\u5199-$id", it.getString(0)) }
                db.update("sample", ContentValues().apply { put("label", "\u66f4\u65b0-$id") }, "id=?", arrayOf(id.toString()))
            }
            db.setTransactionSuccessful(); db.endTransaction()
            val elapsed = System.nanoTime() - started
            repeat(512) { id -> db.rawQuery("SELECT label FROM sample WHERE id=?", arrayOf(id.toString())).use {
                assertTrue(it.moveToFirst()); assertEquals("\u66f4\u65b0-$id", it.getString(0))
            } }
            assertEquals(512L, scalar(db, "SELECT count(*) FROM sample"))
            compilations += db.statementStats.prepared
            println("KNOWLEDGE_STATEMENTS_PROFILE round=$round capacity=$capacity rows=512 transaction_ns=$elapsed " +
                "prepared=${db.statementStats.prepared} reused=${db.statementStats.reused}")
        }
        assertTrue(compilations[1] * 4 < compilations[0])
        assertTrue(compilations[2] * 4 < compilations[3])
    }
}
