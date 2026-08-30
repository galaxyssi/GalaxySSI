package com.signalasi.chat

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConversationDatabaseStressTest {
    @Test
    fun versionOneUpgradePreservesRowsAndIndexesPreviewState() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "agent_conversation_upgrade_${System.nanoTime()}.db"
        val conversation = conversation(7, System.currentTimeMillis())
        val encrypted = AgentRowStorageCipher(context, databaseName).encrypt(
            JSONObject()
                .put("title", conversation.title)
                .put("created_at", conversation.createdAt)
                .put("updated_at", conversation.updatedAt)
                .put("status", conversation.status.name)
                .put("latest_message_indexed", true)
                .put("latest_message_entry_id", conversation.latestMessageEntryId)
                .put("latest_message_preview", conversation.latestMessagePreview)
                .put("latest_message_timestamp_millis", conversation.latestMessageTimestampMillis)
                .toString(),
            "$databaseName:${conversation.id}".toByteArray()
        )
        SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath(databaseName), null).use { legacy ->
            legacy.execSQL(
                """
                CREATE TABLE agent_conversations (
                    conversation_id TEXT PRIMARY KEY NOT NULL,
                    status TEXT NOT NULL,
                    pinned INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    encrypted_payload TEXT NOT NULL
                )
                """.trimIndent()
            )
            legacy.insertOrThrow(
                "agent_conversations",
                null,
                ContentValues().apply {
                    put("conversation_id", conversation.id)
                    put("status", conversation.status.name)
                    put("pinned", 0)
                    put("created_at", conversation.createdAt)
                    put("updated_at", conversation.updatedAt)
                    put("encrypted_payload", encrypted)
                }
            )
            legacy.version = 1
        }

        val database = AgentConversationDatabase(context, databaseName)
        try {
            assertEquals(conversation.title, database.read(conversation.id)?.title)
            assertTrue(database.missingLatestMessageIndex().isEmpty())
            assertEquals(1, database.count())
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun tenThousandEncryptedConversationsRemainPagedAndIndividuallyMutable() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "agent_conversation_stress_${System.nanoTime()}.db"
        val database = AgentConversationDatabase(context, databaseName)
        try {
            val baseTime = System.currentTimeMillis()
            val conversations = List(CONVERSATION_COUNT) { index ->
                conversation(index, baseTime + index)
            }
            val insertStartedAt = SystemClock.elapsedRealtime()
            assertTrue(database.upsertAll(conversations))
            val insertElapsedMillis = SystemClock.elapsedRealtime() - insertStartedAt
            assertEquals(CONVERSATION_COUNT, database.count())
            assertTrue(
                "10,000 encrypted conversation inserts took ${insertElapsedMillis}ms",
                insertElapsedMillis < 120_000L
            )

            val seen = linkedSetOf<String>()
            var cursor: AgentConversationPageCursor? = null
            var hasMore: Boolean
            do {
                val page = database.page(
                    status = null,
                    cursor = cursor,
                    pageSize = PAGE_SIZE
                )
                page.items.forEach { conversation -> assertTrue(seen.add(conversation.id)) }
                cursor = page.nextCursor
                hasMore = page.hasMore
            } while (hasMore && cursor != null)
            assertEquals(CONVERSATION_COUNT, seen.size)

            val targetId = conversationId(CONVERSATION_COUNT / 2)
            val previous = database.read(targetId)
            assertNotNull(previous)
            val updateStartedAt = SystemClock.elapsedRealtimeNanos()
            assertTrue(database.upsert(previous!!.copy(title = "updated-title")))
            val updateMillis = (SystemClock.elapsedRealtimeNanos() - updateStartedAt) / 1_000_000.0
            assertTrue("Single indexed update took ${updateMillis}ms", updateMillis < 100.0)
            assertEquals("updated-title", database.read(targetId)?.title)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    private fun conversation(index: Int, updatedAt: Long): AgentConversation = AgentConversation(
        id = conversationId(index),
        title = "会话压力测试-${(index + 1).toString().padStart(5, '0')}",
        createdAt = updatedAt,
        updatedAt = updatedAt,
        latestMessageIndexed = true,
        latestMessageEntryId = UUID.nameUUIDFromBytes("entry-$index".toByteArray()).toString(),
        latestMessagePreview = "会话压力测试-${(index + 1).toString().padStart(5, '0')}",
        latestMessageTimestampMillis = updatedAt
    )

    private fun conversationId(index: Int): String =
        UUID.nameUUIDFromBytes("conversation-$index".toByteArray()).toString()

    private companion object {
        const val CONVERSATION_COUNT = 10_000
        const val PAGE_SIZE = 200
    }
}
