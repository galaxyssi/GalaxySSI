package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.content.ContentValues
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentTranscriptEntryDatabaseInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val databaseNames = mutableListOf<String>()

    @After
    fun cleanUp() {
        databaseNames.forEach(context::deleteDatabase)
    }

    @Test
    fun retainsAndPagesEveryEntryWithoutCountLimits() {
        val database = database()
        val expectedIds = (0 until 2_105).map { index -> "entry-$index" }
        expectedIds.forEachIndexed { index, id ->
            assertTrue(database.insert(entry(id, "conversation-main", index.toLong())))
        }

        val complete = database.listConversation("conversation-main")
        assertEquals(expectedIds, complete.map(AgentTranscriptEntry::id))

        val pagedIds = mutableListOf<String>()
        var cursor: Long? = null
        do {
            val page = database.listConversationPage(
                conversationId = "conversation-main",
                beforeSequenceExclusive = cursor,
                pageSize = 137
            )
            pagedIds += page.entries.map(AgentTranscriptEntry::id)
            cursor = page.nextBeforeSequence
        } while (page.hasMore)

        assertEquals(expectedIds.size, pagedIds.size)
        assertEquals(expectedIds.toSet(), pagedIds.toSet())
        assertEquals(expectedIds.size, pagedIds.distinct().size)
        database.close()
    }

    @Test
    fun storesLongMessageContentEncryptedWithoutTruncation() {
        val database = database()
        val marker = "private-transcript-marker"
        val text = "content ".repeat(4_000) + marker
        assertTrue(
            database.insert(
                entry("long-entry", "long-conversation", 1L).copy(text = text)
            )
        )

        val preview = database.listConversationPage(
            "long-conversation",
            pageSize = 1
        ).entries.single()
        assertTrue(AgentLargeOutputPolicy.hasDeferredContent(preview))
        assertTrue(preview.text.length < text.length)
        assertEquals(text.length, preview.textLength)
        assertEquals(text, database.listConversation("long-conversation").single().text)
        val encryptedPayload = database.readableDatabase.rawQuery(
            "SELECT encrypted_payload FROM transcript_entries WHERE entry_id = ?",
            arrayOf("long-entry")
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            cursor.getString(0)
        }
        assertFalse(encryptedPayload.contains(marker))
        assertTrue(AgentRowStorageCipher.isEncrypted(encryptedPayload))
        val encryptedChunks = database.readableDatabase.rawQuery(
            """
            SELECT encrypted_chunk
            FROM transcript_entry_chunks
            WHERE entry_id = ? AND field_name = 'text'
            """.trimIndent(),
            arrayOf("long-entry")
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }
        assertTrue(encryptedChunks.size > 1)
        assertTrue(encryptedChunks.none { it.contains(marker) })
        val reconstructed = mutableListOf<String>()
        var offset = 0
        var done = false
        do {
            val page = checkNotNull(
                database.textChunkPage(
                    entryId = "long-entry",
                    offset = offset,
                    pageSize = 2
                )
            )
            reconstructed += page.chunks
            offset = page.nextOffset
            done = page.done
        } while (!done)
        assertEquals(text, reconstructed.joinToString(""))
        database.close()
    }

    @Test
    fun legacyEntryIsReencryptedWithTheSharedPagingKeyAfterRead() {
        val database = database()
        val entry = entry("legacy-entry", "legacy-conversation", 1L)
        assertTrue(database.insert(entry))
        val aad = "agent-transcript-entry:${entry.id}".toByteArray()
        val rowCipher = AgentRowStorageCipher(
            context,
            AgentConversationDatabase.STORAGE_CIPHER_NAMESPACE
        )
        val current = encryptedPayload(database, entry.id)
        val plaintext = checkNotNull(rowCipher.decrypt(current, aad))
        val legacy = AgentStorageCipher.encrypt(plaintext, aad)
        database.writableDatabase.update(
            "transcript_entries",
            ContentValues().apply { put("encrypted_payload", legacy) },
            "entry_id = ?",
            arrayOf(entry.id)
        )
        database.clearRuntimeDecodeCache()

        assertEquals(entry.text, database.findById(entry.id)?.text)
        assertTrue(AgentRowStorageCipher.isEncrypted(encryptedPayload(database, entry.id)))
        database.close()
    }

    @Test
    fun readsOnlyEntriesAddedAfterTheVisibleWindowCursor() {
        val database = database()
        (0 until 5).forEach { index ->
            assertTrue(database.insert(entry("entry-$index", "conversation-main", index.toLong())))
        }
        val initial = database.listConversationPage("conversation-main", pageSize = 2)
        assertEquals(listOf("entry-3", "entry-4"), initial.entries.map(AgentTranscriptEntry::id))

        assertTrue(database.insert(entry("entry-5", "conversation-main", 5L)))
        assertTrue(database.insert(entry("entry-6", "conversation-main", 6L)))
        val delta = database.listConversationAfter(
            conversationId = "conversation-main",
            afterSequenceExclusive = checkNotNull(initial.newestSequence),
            pageSize = 10
        )

        assertEquals(listOf("entry-5", "entry-6"), delta.entries.map(AgentTranscriptEntry::id))
        assertEquals(2, delta.entries.size)
        assertFalse(delta.hasMore)
        database.close()
    }

    @Test
    fun replaceBatchUpdatesRequestedEntriesAndPreservesOtherConversations() {
        val database = database()
        assertTrue(database.insert(entry("unrelated", "conversation-existing", 1L)))
        val original = (0 until 12).map { index ->
            entry("batch-$index", "conversation-batch-${index / 2}", index.toLong() + 10L)
        }
        assertTrue(database.replaceBatch(original))
        assertTrue(database.replaceBatch(original.map { it.copy(text = "updated ${it.id}") }))

        assertEquals("message unrelated", database.findById("unrelated")?.text)
        original.forEach { expected ->
            assertEquals("updated ${expected.id}", database.findById(expected.id)?.text)
        }
        assertEquals(13, database.listAll().size)
        database.close()
    }

    private fun database(): AgentTranscriptEntryDatabase {
        val name = "signalasi_transcript_test_${UUID.randomUUID()}.db"
        databaseNames += name
        return AgentTranscriptEntryDatabase(context, name)
    }

    private fun encryptedPayload(database: AgentTranscriptEntryDatabase, entryId: String): String =
        database.readableDatabase.rawQuery(
            "SELECT encrypted_payload FROM transcript_entries WHERE entry_id = ?",
            arrayOf(entryId)
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            cursor.getString(0)
        }

    private fun entry(id: String, conversationId: String, timestamp: Long) =
        AgentTranscriptEntry(
            id = id,
            role = AgentTranscriptRole.USER,
            text = "message $id",
            timestampMillis = timestamp,
            dedupeKey = "dedupe-$id",
            conversationId = conversationId,
            turnId = "turn-$id",
            taskId = "task-$id"
        )
}
