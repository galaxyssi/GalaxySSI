package com.galaxyssi.chat

import android.os.Process
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentProviderAttemptDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val identity = AgentProviderAttemptReport(901, "test-conversation", "test-turn", "test-task", "test-action")

    @Test fun encryptedJournalReopensWithTheActualFailedProvider() = withStore { name, store ->
        val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
        val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
        tracker.start("request-a", "test-cloud-a", "test-provider", "test-model-private", 100)
        tracker.progress("connected", 10)
        tracker.finish(20, AgentProviderFailure(AgentProviderFailureClass.PERMANENT_CREDENTIAL, false), 401)
        journal.finish(tracker.report)
        store.close()
        val reopened = AgentRunEventStore(context, name)
        try {
            val restored = AgentProviderAttemptJournal(reopened, "test-phone", identity).restore()
            assertEquals(tracker.report, restored)
            assertEquals(AgentRunControlState.FAILED, reopened.snapshot(journal.runId)?.state)
            assertEquals(4, reopened.events(journal.runId).size)
            assertFalse(String(context.getDatabasePath(name).readBytes(), Charsets.ISO_8859_1).contains("test-model-private"))
        } finally { reopened.close() }
    }

    @Test fun unfinishedCallRemainsAnObservationNotASuccess() = withStore { name, store ->
        val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
        val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
        tracker.start("request-a", "test-cloud-a", "test-provider", "test-model", 100)
        tracker.progress("first_output", 10)
        store.close()
        val reopened = AgentRunEventStore(context, name)
        try {
            val restored = requireNotNull(AgentProviderAttemptJournal(reopened, "test-phone", identity).restore())
            assertEquals("first_output", restored.attempts.single().state)
            assertEquals(AgentRunControlState.RUNNING, reopened.snapshot(journal.runId)?.state)
            assertEquals("observation_only", reopened.snapshot(journal.runId)?.lastEvent?.payload?.get("recovery_mode"))
            assertEquals("test-model", restored.mergeMetadata(emptyMap())["resolved_model_id"])
            assertEquals("first_output", restored.mergeMetadata(emptyMap())["provider_attempt_state"])
        } finally { reopened.close() }
    }

    @Test fun duplicateCheckpointIsIdempotent() = withStore { _, store ->
        val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
        val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
        tracker.start("request-a", "test-cloud-a", "test-provider", "test-model", 100)
        repeat(5) { journal.checkpoint(tracker.report) }
        assertEquals(1, store.events(journal.runId).size)
    }

    @Test fun independentConversationAndTurnNeverShareRecords() = withStore { _, store ->
        val identities = listOf(identity, identity.copy(conversationId = "other"), identity.copy(turnId = "other"),
            identity.copy(taskId = "other"), identity.copy(actionId = "other"), identity.copy(sourceMessageId = 902))
        identities.forEachIndexed { index, item ->
            val journal = AgentProviderAttemptJournal(store, "test-phone", item)
            val tracker = AgentProviderAttemptTracker(item, journal::checkpoint)
            tracker.start("request-$index", "test-cloud-$index", "provider", "model", 100)
            tracker.finish(10)
            journal.finish(tracker.report)
        }
        assertEquals(identities.size, identities.map(AgentProviderAttemptJournal::runId).toSet().size)
        identities.forEachIndexed { index, item ->
            assertEquals("test-cloud-$index", AgentProviderAttemptJournal(store, "test-phone", item)
                .restore()!!.attempts.single().resourceId)
        }
    }

    @Test fun durableResponseKeepsFailuresAcrossInboxReopen() {
        val name = "provider-inbox-test-${UUID.randomUUID()}.db"
        val legacy = "provider-inbox-test-${UUID.randomUUID()}"
        val tracker = AgentProviderAttemptTracker(identity)
        tracker.start("request-a", "test-cloud-a", "provider-a", "model-a", 100)
        tracker.finish(10, AgentProviderFailure(AgentProviderFailureClass.PERMANENT_BILLING, false), 402)
        tracker.start("request-b", "test-cloud-b", "provider-b", "model-b", 120)
        tracker.finish(20)
        val response = AgentConnectorResponse(901, "test-cloud-a", "\u6d4b\u8bd5\u56de\u590d", "test-conversation", "test-turn", "test-task",
            resolvedContactId = "test-cloud-b", providerAttempts = tracker.report)
        try {
            AgentConnectorResponseInbox(context, name, legacy).use { inbox -> assertTrue(inbox.append(response)) }
            AgentConnectorResponseInbox(context, name, legacy).use { inbox ->
                val restored = inbox.page().responses.single()
                assertEquals(response, restored)
                val metadata = restored.providerAttempts!!.mergeMetadata(mapOf("remaining_fallback_ids" to "test-cloud-a,codex"))
                assertEquals("codex", metadata["remaining_fallback_ids"])
                assertEquals("test-cloud-b", restored.executionContactId)
            }
        } finally {
            context.deleteDatabase(name)
            context.deleteSharedPreferences(legacy)
        }
    }

    @Test fun wrongReportIdentityCannotOverwriteAnotherRun() = withStore { _, store ->
        val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
        assertTrue(runCatching { journal.checkpoint(identity.copy(turnId = "other")) }.isFailure)
        assertNull(journal.restore())
    }

    @Test fun replayPagesDoNotRepeatTheFullHistoryInEachEvent() = withStore { _, store ->
        val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
        val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
        repeat(140) { index ->
            tracker.start("request-$index", "resource-$index", "provider", "model", index.toLong())
            tracker.finish(10, AgentProviderFailure(AgentProviderFailureClass.TRANSIENT, true))
        }
        journal.finish(tracker.report)
        assertEquals(281, store.events(journal.runId).size)
        assertTrue(store.events(journal.runId).all { event ->
            event.payload.values.sumOf { it.toString().length } < 1_024
        })
        assertEquals(tracker.report, journal.restore())
    }

    @Test fun saveBeforeProcessDeath() {
        val name = processDatabase()
        val store = AgentRunEventStore(context, name)
        try {
            val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
            val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
            tracker.start("process-${Process.myPid()}", "test-cloud-a", "provider", "model", 100)
            tracker.finish(10, AgentProviderFailure(AgentProviderFailureClass.PERMANENT_BILLING, false), 402)
            tracker.start("next-${Process.myPid()}", "test-cloud-b", "provider", "model-b", 120)
            tracker.progress("first_output", 20)
            Log.i("ProviderRecoveryTest", "saved pid=${Process.myPid()}")
        } finally { store.close() }
    }

    @Test fun recoverAfterProcessDeath() {
        val name = processDatabase()
        val store = AgentRunEventStore(context, name)
        try {
            val report = requireNotNull(AgentProviderAttemptJournal(store, "test-phone", identity).restore())
            assertNotEquals("process-${Process.myPid()}", report.attempts.first().requestId)
            assertEquals(402, report.attempts.first().httpStatus)
            assertEquals("first_output", report.attempts.last().state)
            assertEquals("test-cloud-a", report.mergeMetadata(emptyMap())["retried_resource_ids"])
            assertEquals("test-cloud-b", report.mergeMetadata(emptyMap())["resource_id"])
            Log.i("ProviderRecoveryTest", "recovered pid=${Process.myPid()} attempts=${report.attempts.size}")
        } finally { store.close(); context.deleteDatabase(name) }
    }

    private fun processDatabase(): String {
        val token = InstrumentationRegistry.getArguments().getString("providerRecoveryId").orEmpty()
        assumeTrue(token.matches(Regex("provider-process-[0-9a-f-]{36}")))
        return "$token.db"
    }

    private fun withStore(test: (String, AgentRunEventStore) -> Unit) {
        val name = "provider-journal-test-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, name)
        try { test(name, store) } finally { store.close(); context.deleteDatabase(name) }
    }
}
