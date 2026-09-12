package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GalaxySSILinkOutboxDatabaseTest {
    @Test fun onlyExactReceiptBindingAndHashCanDeleteDurableOutboxRow() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "mqtt_receipt_${System.nanoTime()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { database ->
                database.insert(item(1, System.currentTimeMillis()).put("receipt_binding", "a".repeat(64))
                    .put("receipt_hash", "b".repeat(64)))
            }
            GalaxySSILinkOutboxDatabase(context, name).use { database ->
                assertTrue(database.deleteForVerifiedReceipt("message-1", "c".repeat(64), "b".repeat(64)) == null)
                assertTrue(database.deleteForVerifiedReceipt("message-1", "a".repeat(64), "c".repeat(64)) == null)
                assertTrue(database.deleteForVerifiedReceipt("message-other", "a".repeat(64), "b".repeat(64)) == null)
                assertTrue(database.contains("message-1"))
                assertTrue(database.deleteForVerifiedReceipt("message-1", "a".repeat(64), "b".repeat(64)) != null)
                assertFalse(database.contains("message-1"))
                assertTrue(database.deleteForVerifiedReceipt("message-1", "a".repeat(64), "b".repeat(64)) == null)
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun outboxWithoutProofCannotBeRemovedByNetworkReceipt() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "mqtt_receipt_absent_${System.nanoTime()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { database ->
                database.insert(item(1, System.currentTimeMillis()))
                assertTrue(database.deleteForVerifiedReceipt("message-1", "", "") == null)
                assertTrue(database.deleteForVerifiedReceipt("message-1", "a".repeat(64), "b".repeat(64)) == null)
                assertTrue(database.contains("message-1"))
            }
        } finally { context.deleteDatabase(name) }
    }
    @Test fun bulkWakeReadsIndexedScheduleInsteadOfStaleEncryptedRetryDate() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "mqtt_wake_${System.nanoTime()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { database ->
                val now = System.currentTimeMillis()
                database.insert(item(1, now).put("status", "publishing").put("next_attempt_at", now + 60_000))
                database.makePendingImmediatelyRetryable(now)
                val result = database.retryCandidates(now, true, 6, 9, 4)
                assertEquals(1, result.length())
                assertEquals(now, result.getJSONObject(0).getLong("next_attempt_at"))
                assertEquals("queued", result.getJSONObject(0).getString("status"))
                assertEquals(1, GalaxySSILinkDeliveryStore.pendingFromArray(result, now).size)
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun deferredOfflineRowsCannotStarveOlderDueRowsPastLookahead() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "mqtt_fair_${System.nanoTime()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { database ->
                val now = System.currentTimeMillis()
                repeat(40) { database.insert(item(it, now + it).put("next_attempt_at", now)) }
                repeat(32) { index -> database.update("message-$index") { it.put("next_attempt_at", now + 5_000) } }
                val result = database.retryCandidates(now + 6_000, true, 6, 9, 4)
                assertEquals("message-32", result.getJSONObject(0).getString("message_id"))
                assertEquals(0, result.getJSONObject(0).getInt("attempts"))
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun indexedOutboxUpdatesOneRowWithoutRewritingTheQueue() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "galaxyssi_outbox_test_${System.nanoTime()}.db"
        val database = GalaxySSILinkOutboxDatabase(context, databaseName)
        try {
            val now = System.currentTimeMillis()
            repeat(1_000) { index ->
                assertTrue(database.insert(item(index, now + index)))
            }
            assertEquals(1_000, database.count())
            assertTrue(database.hasClientSourceMessageId(1_500L))
            assertFalse(database.hasClientSourceMessageId(9_999L))

            val startedAt = SystemClock.elapsedRealtimeNanos()
            repeat(1_000) { index ->
                assertTrue(database.update("message-$index") { value ->
                    value.put("attempts", value.optInt("attempts") + 1)
                    value.put("status", "publishing")
                })
            }
            val elapsedMillis = (SystemClock.elapsedRealtimeNanos() - startedAt) / 1_000_000L
            assertTrue("1,000 indexed updates took ${elapsedMillis}ms", elapsedMillis < 30_000L)

            val candidates = database.retryCandidates(
                nowMillis = now + 2_000L,
                allowValidatedNetworkMessages = true,
                maxAttempts = 6,
                attachmentMaxAttempts = 6,
                limit = 20
            )
            assertEquals(160, candidates.length())

            repeat(500) { index -> assertTrue(database.delete("message-$index") != null) }
            assertEquals(500, database.count())
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun replaceAllPreservesEncryptedOutboxItems() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "galaxyssi_outbox_replace_test_${System.nanoTime()}.db"
        val database = GalaxySSILinkOutboxDatabase(context, databaseName)
        try {
            val now = System.currentTimeMillis()
            val expected = JSONArray().put(item(1, now)).put(item(2, now + 1L))
            database.replaceAll(expected)
            val restored = database.readAll()
            assertEquals(2, restored.length())
            assertEquals("encrypted-wire-1", restored.getJSONObject(0).getString("wire_payload"))
            assertEquals("encrypted-wire-2", restored.getJSONObject(1).getString("wire_payload"))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun deletesOnlyRequestedClientSourceMessagesAcrossSqlBatches() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "galaxyssi_outbox_batch_delete_test_${System.nanoTime()}.db"
        val database = GalaxySSILinkOutboxDatabase(context, databaseName)
        try {
            val now = System.currentTimeMillis()
            repeat(1_200) { index -> assertTrue(database.insert(item(index, now + index))) }
            val requested = (0 until 1_200 step 2).map { 1_000L + it }
            val deletedMessageIds = mutableSetOf<String>()
            val removed = database.deleteByClientSourceMessageIds(requested) { item ->
                deletedMessageIds += item.getString("message_id")
            }

            assertEquals(600, removed)
            assertEquals(600, deletedMessageIds.size)
            assertEquals(600, database.count())
            assertFalse(database.hasClientSourceMessageId(1_000L))
            assertTrue(database.hasClientSourceMessageId(1_001L))
            assertFalse(database.hasClientSourceMessageId(2_198L))
            assertTrue(database.hasClientSourceMessageId(2_199L))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun bulkDeleteReturnsWalStorageAfterQueueCleanup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "galaxyssi_outbox_checkpoint_test_${System.nanoTime()}.db"
        val database = GalaxySSILinkOutboxDatabase(context, databaseName)
        try {
            val now = System.currentTimeMillis()
            repeat(1_200) { index -> assertTrue(database.insert(item(index, now + index))) }

            assertEquals(
                1_200,
                database.deleteByClientSourceMessageIds((1_000L until 2_200L).toList())
            )

            assertEquals(0, database.count())
            val wal = context.getDatabasePath("$databaseName-wal")
            assertTrue("Bulk cleanup retained ${wal.length()} WAL bytes", wal.length() <= 64 * 1024L)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun versionOneUpgradePreservesQueuedItems() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "galaxyssi_outbox_upgrade_test_${System.nanoTime()}.db"
        GalaxySSILinkOutboxDatabase(context, databaseName).use { database ->
            assertTrue(database.insert(item(7, System.currentTimeMillis())))
        }
        SQLiteDatabase.openDatabase(
            context.getDatabasePath(databaseName).absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE
        ).use { database ->
            database.execSQL("DROP TABLE IF EXISTS row_storage_metadata")
            database.execSQL("PRAGMA user_version = 1")
        }

        try {
            GalaxySSILinkOutboxDatabase(context, databaseName).use { upgraded ->
                assertEquals(1, upgraded.count())
                val restored = upgraded.readAll()
                assertEquals(1, restored.length())
                assertEquals("encrypted-wire-7", restored.getJSONObject(0).getString("wire_payload"))
            }
        } finally {
            context.deleteDatabase(databaseName)
        }
    }

    private fun item(index: Int, createdAt: Long): JSONObject = JSONObject()
        .put("message_id", "message-$index")
        .put("topic", "opaque-topic-${index % 3}")
        .put("status", "queued")
        .put("attempts", 0)
        .put("requires_validated_network", false)
        .put("client_source_message_id", 1_000L + index)
        .put("contact_id", "contact-${index % 3}")
        .put("broker_ack_timeout_millis", 12_000L)
        .put("next_attempt_at", createdAt)
        .put("created_at", createdAt)
        .put("updated_at", createdAt)
        .put("wire_payload", "encrypted-wire-$index")
}
