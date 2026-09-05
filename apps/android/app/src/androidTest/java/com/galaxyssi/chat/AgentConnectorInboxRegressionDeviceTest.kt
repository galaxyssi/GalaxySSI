package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

/** Runs against either the old or new installed App; all storage is test-namespaced. */
@RunWith(AndroidJUnit4::class)
class AgentConnectorInboxRegressionDeviceTest {
    private lateinit var context: InboxRegressionContext

    @Before fun setup() {
        context = InboxRegressionContext(ApplicationProvider.getApplicationContext(), "inbox-regression-${UUID.randomUUID()}")
    }

    @After fun cleanup() {
        AgentConnectorResponseStore.clear(context)
        context.deleteDatabase("galaxyssi_connector_inbox.db")
    }

    private fun append(response: AgentConnectorResponse) {
        // The return type changed from Unit to an insertion receipt; reflection allows the same baseline APK test.
        AgentConnectorResponseStore.javaClass.getMethod("append", Context::class.java, AgentConnectorResponse::class.java)
            .invoke(AgentConnectorResponseStore, context, response)
    }

    private fun response(id: Long = 700001) = AgentConnectorResponse(
        id, "inbox-test-codex", "\u56de\u590d\u4fdd\u5b58\u9a8c\u8bc1-$id", "inbox-test-conversation", "turn-$id", "task-$id")

    @Test fun oldestUnconsumedReplySurvives128Arrivals() {
        val first = response()
        repeat(128) { append(response(first.sourceMessageId + it)) }
        assertTrue("Unconsumed replies must not be evicted by later replies", AgentConnectorResponseStore.contains(context, first))
    }

    @Test fun unconsumedReplySurvivesMoreThanOneDay() {
        val old = response().copy(receivedAtMillis = System.currentTimeMillis() - 3L * 24 * 60 * 60 * 1000)
        append(old)
        assertTrue("Age alone must not discard a pending result", AgentConnectorResponseStore.contains(context, old))
    }

    @Test fun fullLongAnswerSurvivesPersistence() {
        val long = response().copy(content = "\u5b8c\u6574\u7b54\u6848".repeat(24000))
        append(long)
        val restored = AgentConnectorResponseStore.pending(context).single().content
        assertEquals("Long response length must survive persistence", long.content.length, restored.length)
        assertTrue("Long response content must survive persistence", long.content == restored)
    }

    @Test fun sameSourceCannotAcknowledgeAnotherConversation() {
        val original = response()
        append(original)
        assertFalse(AgentConnectorResponseStore.remove(context, original.copy(conversationId = "another-conversation")))
        assertTrue(AgentConnectorResponseStore.contains(context, original))
    }
}

private class InboxRegressionContext(base: Context, private val prefix: String) : ContextWrapper(base) {
    override fun getApplicationContext(): Context = this
    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = super.getSharedPreferences("$prefix-$name", mode)
    override fun getDatabasePath(name: String): File = super.getDatabasePath("$prefix-$name")
    override fun deleteDatabase(name: String): Boolean = super.deleteDatabase("$prefix-$name")
    override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
        baseContext.openOrCreateDatabase("$prefix-$name", mode, factory)
    override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
                                     errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
        baseContext.openOrCreateDatabase("$prefix-$name", mode, factory, errorHandler)
}
