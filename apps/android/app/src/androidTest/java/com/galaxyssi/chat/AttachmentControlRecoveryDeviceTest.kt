package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executor
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Isolated durable inboxes; does not publish packets or modify user contacts. */
class AttachmentControlRecoveryDeviceTest {
    @Test fun rejectedPublicationSurvivesRepositoryRecreationUntilReplayCommits() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        for (rejectedStage in listOf("status", "manifest", "chunk", "missing", "failed")) {
            val database = AgentEncryptedDatabase(context, "test_attachment_recovery_${UUID.randomUUID()}")
            try {
                val inbox = GalaxySSILinkInbox(database)
                val peer = GalaxySSILinkInbox.Peer("isolated-pair", "isolated-desktop", false)
                val body = JSONObject().put("type", "input_attachment_request")
                    .put("message_id", "recovery-request").put("request_id", "a".repeat(32))
                val digest = "b".repeat(64)
                val stored = inbox.accept(peer, "recovery-request", MqttImmutableContent.hash(body),
                    body, digest, true)
                var failed = 0
                AttachmentControlInbox(Executor(Runnable::run)).enqueue(stored.recordKey,
                    process = { MqttPublishResult.FAILED.requireAttachmentQueued() },
                    complete = { inbox.complete(stored.payload); fail("$rejectedStage retired before commit") },
                    failed = { failed++ })
                assertEquals(1, failed)
                assertTrue(inbox.isPending(stored.payload))

                val reopened = GalaxySSILinkInbox(database)
                val recovered = requireNotNull(reopened.replay(peer.scope, digest))
                assertFalse(recovered.completed)
                assertEquals(stored.recordKey, recovered.recordKey)
                val pending = JSONObject(reopened.pending().single().payload)
                var completed = 0
                AttachmentControlInbox(Executor(Runnable::run)).enqueue(stored.recordKey,
                    process = { MqttPublishResult.QUEUED.requireAttachmentQueued() },
                    complete = { assertTrue(reopened.complete(pending)); completed++ },
                    failed = { throw it })
                assertEquals(1, completed)
                assertTrue(reopened.pending().isEmpty())
                assertTrue(requireNotNull(inbox.replay(peer.scope, digest)).completed)
            } finally {
                GalaxySSILinkInbox(database).clear()
                database.clear()
            }
        }
    }

    @Test fun failedReceiptDoesNotCompleteAnotherPeersRecoveryRequest() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val database = AgentEncryptedDatabase(context, "test_attachment_peers_${UUID.randomUUID()}")
        try {
            val inbox = GalaxySSILinkInbox(database)
            val body = JSONObject().put("type", "input_attachment_receipt").put("message_id", "same-id")
            val digest = "c".repeat(64)
            val first = inbox.accept(GalaxySSILinkInbox.Peer("pair-a", "a", false), "same-id",
                MqttImmutableContent.hash(body), body, digest, true)
            val second = inbox.accept(GalaxySSILinkInbox.Peer("pair-b", "b", false), "same-id",
                MqttImmutableContent.hash(body), body, digest, true)
            val processor = AttachmentControlInbox(Executor(Runnable::run))
            processor.enqueue(first.recordKey, { MqttPublishResult.FAILED.requireAttachmentQueued() },
                { fail("Rejected chunk retired") }, { })
            processor.enqueue(second.recordKey, { MqttPublishResult.QUEUED.requireAttachmentQueued() },
                { assertTrue(inbox.complete(second.payload)) }, { throw it })
            assertTrue(inbox.isPending(first.payload))
            assertFalse(inbox.isPending(second.payload))
            assertEquals(first.recordKey, inbox.pending().single().recordKey)
        } finally {
            GalaxySSILinkInbox(database).clear()
            database.clear()
        }
    }
}
