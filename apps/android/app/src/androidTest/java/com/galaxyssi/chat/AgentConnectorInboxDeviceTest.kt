package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConnectorInboxDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private lateinit var databaseName: String
    private lateinit var preferences: String
    private lateinit var inbox: AgentConnectorResponseInbox

    @Before fun setup() {
        val id = UUID.randomUUID().toString()
        databaseName = "test-inbox-$id.db"
        preferences = "test-inbox-legacy-$id"
        inbox = AgentConnectorResponseInbox(context, databaseName, preferences)
    }

    @After fun cleanup() {
        inbox.close()
        context.deleteDatabase(databaseName)
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().clear().commit()
        AgentEncryptedPreferenceCache.clearNamespace(preferences)
    }

    private fun reply(id: Long) = AgentConnectorResponse(id, "test-provider",
        "\u6062\u590d\u9a8c\u8bc1-$id", "conversation-$id", "turn-$id", "task-$id")

    private fun reopen() {
        inbox.close()
        inbox = AgentConnectorResponseInbox(context, databaseName, preferences)
    }

    private fun database(): SQLiteDatabase = SQLiteDatabase.openDatabase(
        context.getDatabasePath(databaseName).absolutePath, null, SQLiteDatabase.OPEN_READWRITE)

    private fun all(): List<AgentConnectorResponse> {
        val end = inbox.highWatermark()
        var cursor = 0L
        return buildList {
            while (cursor < end) {
                val page = inbox.page(cursor, end)
                assertTrue(page.responses.size <= AgentConnectorResponseInbox.PAGE_SIZE)
                assertEquals(0, page.unreadableCount)
                assertTrue(page.nextSequence > cursor)
                addAll(page.responses)
                cursor = page.nextSequence
            }
        }
    }

    @Test fun persists257RepliesWithoutAgeOrCountEvictionInIndexedPages() {
        val expected = (1L..257).map { reply(it).copy(receivedAtMillis = it) }
        expected.forEach { assertTrue(inbox.append(it)) }
        reopen()
        assertEquals(expected, all())
        database().use { db ->
            db.rawQuery("EXPLAIN QUERY PLAN SELECT sequence FROM inbox WHERE handled=0 AND sequence>0 AND sequence<=300 ORDER BY sequence LIMIT 32", null)
                .use { cursor -> assertTrue(cursor.moveToFirst()); assertTrue(cursor.getString(3).contains("inbox_pending")) }
        }
    }

    @Test fun duplicatePendingPayloadCannotOverwriteCanonicalReply() {
        val original = reply(1)
        assertTrue(inbox.append(original))
        assertFalse(inbox.append(original.copy(content = "different", receivedAtMillis = 2)))
        assertEquals(original, inbox.find(original))
        assertEquals(listOf(original), all())
    }

    @Test fun acknowledgedDuplicatesStayHandledAcrossReopen() {
        val response = reply(1)
        inbox.append(response)
        assertTrue(inbox.acknowledge(response))
        reopen()
        assertFalse(inbox.append(response))
        assertFalse(inbox.contains(response))
        assertNull(inbox.find(response))
        database().use { db -> db.rawQuery("SELECT handled, encrypted_value FROM inbox", null).use {
            assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)); assertTrue(it.isNull(1))
        } }
    }

    @Test fun allExecutionDimensionsAreIsolated() {
        val first = reply(1)
        val responses = listOf(first, first.copy(contactId = "other-provider"), first.copy(conversationId = "other-conversation"),
            first.copy(turnId = "other-turn"), first.copy(taskId = "other-task"))
        responses.forEach { inbox.append(it) }
        assertTrue(inbox.acknowledge(first))
        assertEquals(responses.drop(1), all())
    }

    @Test fun terminalTurnAcknowledgementDoesNotClearOtherTurnsOrConversations() {
        val first = reply(1)
        val sibling = first.copy(sourceMessageId = 2, taskId = "continuation")
        val other = first.copy(sourceMessageId = 3, conversationId = "other-conversation")
        listOf(first, sibling, other).forEach { inbox.append(it) }
        inbox.acknowledgeTurn(first.conversationId, first.turnId)
        assertFalse(inbox.containsTurn(first.conversationId, first.turnId))
        assertTrue(inbox.containsTurn(other.conversationId, other.turnId))
        assertEquals(listOf(other), all())
    }

    @Test fun longEncryptedRowsAvoidCursorWindowAndBoundFollowingPage() {
        val large = reply(1).copy(content = "\u5185\u5bb9".repeat(600000))
        inbox.append(large)
        inbox.append(reply(2))
        reopen()
        val firstPage = inbox.page()
        assertEquals(1, firstPage.responses.size)
        assertTrue("Oversized reply must remain complete", large == firstPage.responses.single())
        assertEquals(listOf(reply(2)).map { it.content }, inbox.page(firstPage.nextSequence).responses.map { it.content })
        assertTrue("Chunked read must preserve the full response", large.content == inbox.find(large)?.content)
    }

    @Test fun recoveryHighWatermarkDoesNotChaseNewArrivalsOrSkipExistingOnAck() {
        (1L..90).forEach { inbox.append(reply(it)) }
        val end = inbox.highWatermark()
        val firstPage = inbox.page(throughSequence = end)
        firstPage.responses.forEach { inbox.acknowledge(it) }
        inbox.append(reply(91))
        val rest = mutableListOf<AgentConnectorResponse>()
        var cursor = firstPage.nextSequence
        while (cursor < end) {
            val page = inbox.page(cursor, end)
            rest += page.responses
            assertTrue(page.nextSequence > cursor)
            cursor = page.nextSequence
        }
        assertEquals((33L..90).toList(), rest.map { it.sourceMessageId })
        assertTrue(inbox.contains(reply(91)))
    }

    @Test fun legacyMigrationIsCompleteEncryptedAndIdempotent() {
        val expected = (1L..70).map { reply(it).copy(receivedAtMillis = 1, resolvedContactId = "backup") }
        val array = JSONArray().also { values -> expected.forEach { values.put(AgentConnectorResponseCodec.encode(it)) } }
        AgentEncryptedPreferences(context, preferences).writeString("responses", array.toString())
        assertEquals(expected, all())
        assertFalse(context.getSharedPreferences(preferences, Context.MODE_PRIVATE).contains("responses"))
        reopen()
        assertEquals(expected, all())
        database().use { db -> db.rawQuery("SELECT identity_key,turn_key,encrypted_value FROM inbox LIMIT 1", null).use {
            assertTrue(it.moveToFirst()); assertTrue(it.getString(0).matches(Regex("[a-f0-9]{64}")))
            assertTrue(it.getString(1).matches(Regex("[a-f0-9]{64}")))
            assertTrue(it.getString(2).startsWith("enc:v1:")); assertFalse(it.getString(2).contains(expected.first().content))
        } }
    }

    @Test fun malformedLegacyItemRollsBackWholeMigrationAndKeepsSource() {
        val array = JSONArray().put(AgentConnectorResponseCodec.encode(reply(1))).put(JSONObject().put("content", "invalid"))
        AgentEncryptedPreferences(context, preferences).writeString("responses", array.toString())
        assertThrows(Exception::class.java) { inbox.page() }
        assertTrue(context.getSharedPreferences(preferences, Context.MODE_PRIVATE).contains("responses"))
        database().use { db -> db.rawQuery("SELECT COUNT(*) FROM inbox", null).use { it.moveToFirst(); assertEquals(0, it.getInt(0)) } }
        AgentEncryptedPreferences(context, preferences).writeString("responses", JSONArray().put(AgentConnectorResponseCodec.encode(reply(1))).toString())
        assertEquals(1, all().size)
    }

    @Test fun staleLegacyFileCannotResurrectAcknowledgedResponse() {
        val response = reply(1)
        val array = JSONArray().put(AgentConnectorResponseCodec.encode(response)).toString()
        AgentEncryptedPreferences(context, preferences).writeString("responses", array)
        assertEquals(listOf(response), all())
        inbox.acknowledge(response)
        AgentEncryptedPreferences(context, preferences).writeString("responses", array)
        reopen()
        assertTrue(all().isEmpty())
        assertFalse(inbox.append(response))
    }

    @Test fun unreadableRowIsRetainedWithoutBlockingOtherReplies() {
        val first = reply(1)
        inbox.append(first)
        inbox.append(reply(2))
        inbox.close()
        database().use { db -> db.execSQL("UPDATE inbox SET encrypted_value=(SELECT encrypted_value FROM inbox WHERE sequence=2) WHERE sequence=1") }
        inbox = AgentConnectorResponseInbox(context, databaseName, preferences)
        val page = inbox.page()
        assertEquals(1, page.unreadableCount)
        assertEquals(listOf(2L), page.responses.map { it.sourceMessageId })
        assertTrue(inbox.contains(first))
        assertEquals(2L, page.nextSequence)
    }

    @Test fun concurrentDuplicateWritersCommitEachIdentityOnlyOnce() {
        val pool = Executors.newFixedThreadPool(4)
        try {
            val jobs = (0 until 4).map { Callable { (1L..64).forEach { inbox.append(reply(it)) } } }
            pool.invokeAll(jobs, 60, TimeUnit.SECONDS).forEach { it.get(30, TimeUnit.SECONDS) }
            assertEquals((1L..64).toSet(), all().map { it.sourceMessageId }.toSet())
            assertEquals(64, all().size)
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS)) }
    }
}
