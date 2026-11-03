package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentEncryptedDatabaseCacheDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val name = "test_encrypted_row_cache_${UUID.randomUUID()}"
    private val database = AgentEncryptedDatabase(context, name)

    @After fun cleanup() {
        database.clear()
        RuntimeSensitiveCaches.clearAll()
    }

    @Test fun cachedReadsAlwaysCheckCurrentCiphertextAndRowAssociatedData() {
        database.writeString("one", "first")
        database.writeString("two", "second")
        assertEquals("first", database.readString("one", "missing"))
        external { sql ->
            val changed = AgentStorageCipher.encrypt("external", "database:$name:one".toByteArray())
            sql.execSQL("UPDATE encrypted_values SET encrypted_value = ? WHERE storage_key = 'one'", arrayOf(changed))
        }
        assertEquals("external", database.readString("one", "missing"))
        external { sql ->
            sql.execSQL("UPDATE encrypted_values SET encrypted_value = " +
                "(SELECT encrypted_value FROM encrypted_values WHERE storage_key = 'two') WHERE storage_key = 'one'")
        }
        assertEquals("rejected", database.readString("one", "rejected"))
        assertEquals("second", database.readString("two", "missing"))
    }

    @Test fun instancesShareCommittedRowsButRollbackNeverPublishes() {
        database.writeString("task", "committed")
        val other = AgentEncryptedDatabase(context, name)
        assertEquals("committed", other.readString("task", "missing"))
        val failed = runCatching {
            database.mutateStrings(mapOf("task" to "rolled back", "new" to "uncommitted"),
                onMutation = { sql, key, _ ->
                    assertTrue(sql.inTransaction())
                    assertNull(cached(sql, key))
                    if (key == "new") error("rollback")
                })
        }
        assertEquals("rollback", failed.exceptionOrNull()?.message)
        external { assertNull(cached(it, "task")) }
        assertEquals("committed", other.readString("task", "missing"))
        assertEquals("missing", other.readString("new", "missing"))
        other.writeString("task", "next commit")
        assertEquals("next commit", database.readString("task", "missing"))
    }

    @Test fun nestedWritesAndReadsCannotCacheUncommittedPlaintext() {
        database.writeString("task", "committed")
        val failed = runCatching {
            database.indexedTransaction { sql ->
                database.writeString("task", "uncommitted")
                assertEquals("uncommitted", database.readString("task", "missing"))
                assertNull(cached(sql, "task"))
                database.mutateStrings(mapOf("other" to "also uncommitted"))
                assertEquals("also uncommitted", database.readString("other", "missing"))
                assertNull(cached(sql, "other"))
                error("rollback outer transaction")
            }
        }
        assertEquals("rollback outer transaction", failed.exceptionOrNull()?.message)
        external { assertNull(cached(it, "task")) }
        assertEquals("committed", database.readString("task", "missing"))
        assertEquals("missing", database.readString("other", "missing"))
    }

    @Test fun writesPublishOnlyAfterSuccessfulDurableCommit() {
        database.writeString("single", "committed single")
        external { assertEquals("committed single", cached(it, "single")) }
        database.mutateStrings(mapOf("one" to "first", "two" to "second"),
            onMutation = { sql, key, _ ->
                assertTrue(sql.inTransaction())
                assertNull(cached(sql, key))
            })
        external { sql ->
            assertEquals("first", cached(sql, "one"))
            assertEquals("second", cached(sql, "two"))
            sql.execSQL("CREATE TRIGGER reject_cache_test BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key = 'single' BEGIN SELECT RAISE(ABORT, 'test rejected'); END")
        }
        assertTrue(runCatching { database.writeString("single", "rejected write") }.isFailure)
        external { assertNull(cached(it, "single")) }
        assertEquals("committed single", database.readString("single", "missing"))
    }

    @Test fun lifecycleClearDuringTransactionPreventsPostCommitCachePublication() {
        database.mutateStrings(mapOf("task" to "committed"), onMutation = { _, _, _ ->
            RuntimeSensitiveCaches.clearAll()
        })
        external { assertNull(cached(it, "task")) }
        assertEquals("committed", database.readString("task", "missing"))
    }

    @Test fun closeAndRecreateAfterBackgroundClearReadsDurableRows() {
        database.writeString("task", "durable")
        val oldCiphertext = external { requireNotNull(encrypted(it, "task")) }
        database.close()
        RuntimeSensitiveCaches.clearAll()
        assertNull(AgentEncryptedRowCache.shared.read(database.storageIdentity, "task", oldCiphertext) { null })
        // Connections are process-scoped; recreate the repository, not the shared pool.
        val recreated = AgentEncryptedDatabase(context, name)
        assertEquals("durable", recreated.readString("task", "missing"))
        recreated.writeString("task", "updated")
        assertEquals("updated", database.readString("task", "missing"))
        recreated.clear()
        assertEquals("missing", database.readString("task", "missing"))
        recreated.close()
    }

    @Test fun anotherDatabaseCannotReuseCachedPlaintextForCopiedCiphertext() {
        database.writeString("task", "private to first database")
        val ciphertext = external { requireNotNull(encrypted(it, "task")) }
        val otherName = "${name}_other"
        val other = AgentEncryptedDatabase(context, otherName)
        try {
            other.writeString("task", "private to other database")
            SQLiteDatabase.openDatabase(context.getDatabasePath("$otherName.db").absolutePath, null,
                SQLiteDatabase.OPEN_READWRITE).use { sql ->
                sql.execSQL("UPDATE encrypted_values SET encrypted_value = ? WHERE storage_key = 'task'", arrayOf(ciphertext))
            }
            assertEquals("rejected", other.readString("task", "rejected"))
            assertEquals("private to first database", database.readString("task", "missing"))
        } finally {
            other.clear()
            other.close()
        }
    }

    @Test fun batchAndTypedReadsRespectWritesDeletesAndRuntimeWipes() {
        database.mutateStrings(mapOf("one" to "first", "two" to "second"))
        assertEquals(mapOf("one" to "first", "two" to "second"), database.readStrings(listOf("one", "two")))
        assertEquals(mapOf("one" to "first"), database.readDecodedRows(listOf("one")) { _, _, decode -> decode() })
        RuntimeSensitiveCaches.clearAll()
        assertEquals("first", database.readString("one", "missing"))
        database.removeAll(listOf("one", "two"))
        assertTrue(database.readStrings(listOf("one", "two")).isEmpty())
        database.writeString("one", "new")
        database.remove("one")
        assertEquals("missing", database.readString("one", "missing"))
    }

    @Test fun streamingRollbackAndExternalDeletionCannotResurrectCachedRows() {
        database.writeString("task", "committed")
        val failed = runCatching {
            database.mutateStreaming(sequence {
                yield("task" to "uncommitted")
                error("rollback stream")
            }, removals = { emptySequence() })
        }
        assertEquals("rollback stream", failed.exceptionOrNull()?.message)
        assertEquals("committed", database.readString("task", "missing"))
        external { it.execSQL("DELETE FROM encrypted_values WHERE storage_key = 'task'") }
        assertEquals("missing", database.readString("task", "missing"))
    }

    @Test fun reportColdAndWarmReadLatencyWithoutTimingThresholds() {
        val payload = "checkpoint-value ".repeat(1024)
        database.writeString("benchmark", payload)
        val coldNanos = mutableListOf<Long>()
        val warmNanos = mutableListOf<Long>()
        repeat(13) {
            AgentEncryptedRowCache.shared.clearSensitive()
            var start = SystemClock.elapsedRealtimeNanos()
            val cold = database.readString("benchmark", "missing")
            coldNanos += SystemClock.elapsedRealtimeNanos() - start
            start = SystemClock.elapsedRealtimeNanos()
            val warm = database.readString("benchmark", "missing")
            warmNanos += SystemClock.elapsedRealtimeNanos() - start
            assertEquals(payload, cold)
            assertEquals(payload, warm)
        }
        Log.i("GalaxySSIStorageCache", "read_samples=13 payload_chars=${payload.length} " +
            "cold_median_ns=${coldNanos.sorted()[6]} warm_median_ns=${warmNanos.sorted()[6]}")
    }

    private fun cached(sql: SQLiteDatabase, key: String): String? = encrypted(sql, key)?.let {
        AgentEncryptedRowCache.shared.read(database.storageIdentity, key, it) { null }
    }

    private fun encrypted(sql: SQLiteDatabase, key: String): String? = sql.rawQuery(
        "SELECT encrypted_value FROM encrypted_values WHERE storage_key = ?", arrayOf(key)
    ).use { if (it.moveToFirst()) it.getString(0) else null }

    private fun <T> external(block: (SQLiteDatabase) -> T): T =
        SQLiteDatabase.openDatabase(context.getDatabasePath("$name.db").absolutePath, null,
            SQLiteDatabase.OPEN_READWRITE).use(block)
}
