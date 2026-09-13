package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConnectorUsageInstrumentedTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val usage = AgentConnectorUsage("a".repeat(64), 20, 10, 3)
    private val conversation = AgentConversation("usage-test", "usage test", createdAt = 1, updatedAt = 2)

    private fun databaseTest(block: (String, AgentConversationDatabase) -> Unit) {
        val name = "connector_usage_${UUID.randomUUID()}.db"
        try {
            AgentConversationDatabase(context, name).use { db ->
                check(db.upsert(conversation))
                block(name, db)
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun duplicateFinalUsageCommitsOnceAndSurvivesReopen() = databaseTest { name, db ->
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
        assertNull(db.recordUsageOnce(conversation.id, usage))
        AgentConversationDatabase(context, name).use { reopened ->
            assertNull(reopened.recordUsageOnce(conversation.id, usage))
            assertEquals(usage.applyTo(conversation), reopened.read(conversation.id))
        }
    }

    @Test fun twoDifferentExecutionsAccumulate() = databaseTest { _, db ->
        db.recordUsageOnce(conversation.id, usage)
        db.recordUsageOnce(conversation.id, usage.copy(key = "b".repeat(64)))
        assertEquals(40L, db.read(conversation.id)?.inputTokens)
        assertEquals(20L, db.read(conversation.id)?.outputTokens)
        assertEquals(6L, db.read(conversation.id)?.costMicros)
    }

    @Test fun conflictingCountersOrConversationCannotReuseReceipt() = databaseTest { _, db ->
        db.recordUsageOnce(conversation.id, usage)
        db.upsert(conversation.copy(id = "another-conversation"))
        assertTrue(runCatching { db.recordUsageOnce(conversation.id, usage.copy(inputTokens = 99)) }.isFailure)
        assertTrue(runCatching { db.recordUsageOnce("another-conversation", usage) }.isFailure)
        assertEquals(20L, db.read(conversation.id)?.inputTokens)
        assertEquals(0L, db.read("another-conversation")?.inputTokens)
    }

    @Test fun absentConversationIsNotResurrectedOrMarkedHandled() = databaseTest { _, db ->
        assertTrue(runCatching { db.recordUsageOnce("missing", usage) }.isFailure)
        assertNull(db.read("missing"))
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
    }

    @Test fun receiptInsertFailureRollsBackAlreadyWrittenCounters() = databaseTest { _, db ->
        db.writableDatabase.execSQL("CREATE TRIGGER reject_usage BEFORE INSERT ON " +
            AgentConversationDatabase.TABLE_USAGE_RECEIPTS + " BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        assertTrue(runCatching { db.recordUsageOnce(conversation.id, usage) }.isFailure)
        assertEquals(conversation, db.read(conversation.id))
        db.writableDatabase.execSQL("DROP TRIGGER reject_usage")
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
        assertEquals(usage.applyTo(conversation), db.read(conversation.id))
    }

    @Test fun tenIndependentHelpersRaceOneReceipt() = databaseTest { name, db ->
        val helpers = List(10) { AgentConversationDatabase(context, name).also { it.prepareForPaging() } }
        val executor = Executors.newFixedThreadPool(10)
        try {
            val jobs = helpers.map { helper -> executor.submit<Boolean> {
                helper.recordUsageOnce(conversation.id, usage) != null
            } }
            assertEquals(1, jobs.count { it.get(30, TimeUnit.SECONDS) })
            assertEquals(usage.applyTo(conversation), db.read(conversation.id))
        } finally {
            executor.shutdown()
            check(executor.awaitTermination(30, TimeUnit.SECONDS))
            helpers.forEach { it.close() }
        }
    }

    @Test fun receiptsFollowConversationDeletionAndClear() = databaseTest { _, db ->
        db.recordUsageOnce(conversation.id, usage)
        assertNotNull(db.delete(conversation.id))
        db.upsert(conversation)
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
        db.clear()
        db.upsert(conversation)
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
    }

    @Test fun replacingUnrelatedRowsPreservesRetainedReceipts() = databaseTest { _, db ->
        db.recordUsageOnce(conversation.id, usage)
        db.replaceAll(listOf(checkNotNull(db.read(conversation.id)), conversation.copy(id = "other")))
        assertNull(db.recordUsageOnce(conversation.id, usage))
        db.replaceAll(listOf(conversation.copy(id = "other")))
        db.upsert(conversation)
        assertNotNull(db.recordUsageOnce(conversation.id, usage))
    }

    @Test fun versionSixUpgradePreservesConversation() {
        val name = "connector_usage_upgrade_${UUID.randomUUID()}.db"
        try {
            AgentConversationDatabase(context, name).use { db ->
                db.upsert(conversation)
                db.writableDatabase.execSQL("DROP TABLE ${AgentConversationDatabase.TABLE_USAGE_RECEIPTS}")
                db.writableDatabase.version = 6
            }
            AgentConversationDatabase(context, name).use { db ->
                assertEquals(conversation, db.read(conversation.id))
                assertNotNull(db.recordUsageOnce(conversation.id, usage))
            }
        } finally { context.deleteDatabase(name) }
    }
}
