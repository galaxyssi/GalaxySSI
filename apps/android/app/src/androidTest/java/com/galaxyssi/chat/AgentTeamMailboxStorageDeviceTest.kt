package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated encrypted stores only; never opens a real team, calls a model, or changes phone settings. */
@RunWith(AndroidJUnit4::class)
class AgentTeamMailboxStorageDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun message(index: Int) = AgentTeamMessageEnvelope(messageId = "message-$index", teamId = "fixture",
        conversationId = "fixture", supervisorRunId = "fixture-run", fromInstanceId = "author", toInstanceId = "peer",
        kind = AgentTeamMessageKind.REVIEW, text = "Synthetic independent challenge $index", sequence = index.toLong(),
        state = if (index == 1) AgentTeamMessageState.PENDING else AgentTeamMessageState.ACKNOWLEDGED,
        createdAtMillis = 100L, deliveredAtMillis = if (index == 1) 0L else 200L,
        acknowledgedAtMillis = if (index == 1) 0L else 250L)

    @Test fun legacyHistoryBeyondOldCapAndPendingRequestSurviveEncryptedReopen() {
        val name = "test_team_mailbox_${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, name)
        try {
            val original = (1..5_005).map(::message)
            database.writeString("messages", AgentTeamMessageCodec.encode(original).toString())
            val mailbox = EncryptedAgentTeamMailbox(database)
            assertEquals(listOf(original.first()), mailbox.pendingMessages("fixture-run", "peer"))
            assertFalse(database.contains("messages"))
            val reopened = EncryptedAgentTeamMailbox(AgentEncryptedDatabase(context, name))
            assertEquals(original, reopened.messages("fixture-run"))
            assertEquals(5_006L, reopened.append(message(5_006)).sequence)
            val acknowledged = reopened.acknowledge("message-1", 300L)!!
            assertTrue(EncryptedAgentTeamMailbox(AgentEncryptedDatabase(context, name)).pendingMessages("fixture-run", "peer").isEmpty())
            assertEquals(acknowledged, reopened.append(original.first()))
        } finally { database.clear() }
    }

    @Test fun interruptedEncryptedMigrationRollsBackAndCanRetryWithoutLosingOriginal() {
        val database = AgentEncryptedDatabase(context, "test_team_mailbox_${UUID.randomUUID()}")
        try {
            val original = (1..20).map(::message)
            val raw = AgentTeamMessageCodec.encode(original).toString()
            database.writeString("messages", raw)
            val failing = IndexedAgentTeamMailbox(object : AgentTeamMailboxRows {
                override fun read(key: String) = database.readString(key, "").takeIf(String::isNotEmpty)
                override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
                override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) {
                    var count = 0
                    database.mutateStrings(values, removeKeys, onMutation = { _, _, _ ->
                        if (++count == 7) error("Synthetic interrupted migration")
                    })
                }
            })
            assertTrue(runCatching { failing.pendingMessages("fixture-run", "peer") }.isFailure)
            assertEquals(raw, database.readString("messages", ""))
            assertTrue(database.keys("mailbox.v2/").isEmpty())
            assertEquals(original, EncryptedAgentTeamMailbox(database).messages("fixture-run"))
        } finally { database.clear() }
    }

    @Test fun corruptCiphertextIsNotReplacedByAnEmptyMailbox() {
        val database = AgentEncryptedDatabase(context, "test_team_mailbox_${UUID.randomUUID()}")
        try {
            database.writeString("messages", AgentTeamMessageCodec.encode(listOf(message(1))).toString())
            database.indexedTransaction { sql ->
                sql.execSQL("UPDATE encrypted_values SET encrypted_value = ? WHERE storage_key = ?", arrayOf("invalid-ciphertext", "messages"))
            }
            assertTrue(runCatching { EncryptedAgentTeamMailbox(database).append(message(2)) }.isFailure)
            assertTrue(database.contains("messages"))
            assertTrue(database.keys("mailbox.v2/").isEmpty())
        } finally { database.clear() }
    }
}
