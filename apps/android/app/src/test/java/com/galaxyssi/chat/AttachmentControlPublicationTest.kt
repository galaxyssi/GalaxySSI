package com.galaxyssi.chat

import java.util.concurrent.Executor
import org.junit.Assert.*
import org.junit.Test

class AttachmentControlPublicationTest {
    @Test fun queueCommitIsEnoughButRejectionIsNotCompletion() {
        MqttPublishResult.QUEUED.requireAttachmentQueued()
        MqttPublishResult.PUBLISHED.requireAttachmentQueued()
        assertThrows(IllegalStateException::class.java) {
            MqttPublishResult.FAILED.requireAttachmentQueued()
        }
    }

    @Test fun rejectedStatusManifestOrChunkRetainsTheSameControlForReplay() {
        val publications = listOf("transferring", "manifest", "chunk-0", "chunk-1")
        for (rejectedIndex in publications.indices) {
            val inbox = AttachmentControlInbox(Executor(Runnable::run))
            val sent = mutableListOf<String>()
            var completed = 0
            var retained = 0
            var reject = true
            val process = {
                publications.forEachIndexed { index, item ->
                    val result = if (reject && index == rejectedIndex) MqttPublishResult.FAILED
                        else MqttPublishResult.QUEUED
                    result.requireAttachmentQueued()
                    sent += item
                }
            }
            inbox.enqueue("same-request", process, { completed++ }, { retained++ })
            assertEquals("stage $rejectedIndex completed prematurely", 0, completed)
            assertEquals(1, retained)
            assertEquals(publications.take(rejectedIndex), sent)
            reject = false
            inbox.enqueue("same-request", process, { completed++ }, { throw it })
            assertEquals(1, completed)
            assertEquals(publications.take(rejectedIndex) + publications, sent)
        }
    }

    @Test fun rejectedMissingOrFailureResponseAlsoRemainsReplayable() {
        for (status in listOf("missing", "restore-failed", "prepare-failed")) {
            val inbox = AttachmentControlInbox(Executor(Runnable::run))
            var completed = false
            var retained = false
            inbox.enqueue(status, { MqttPublishResult.FAILED.requireAttachmentQueued() },
                { completed = true }, { retained = true })
            assertFalse(completed)
            assertTrue(retained)
            inbox.enqueue(status, { MqttPublishResult.QUEUED.requireAttachmentQueued() },
                { completed = true }, { throw it })
            assertTrue(completed)
        }
    }

    @Test fun queuedRetryDoesNotStartAConcurrentSecondHandler() {
        val queue = mutableListOf<Runnable>()
        val inbox = AttachmentControlInbox(Executor(queue::add))
        var attempts = 0
        var retained = 0
        repeat(3) {
            inbox.enqueue("missing-chunk", {
                attempts++
                MqttPublishResult.FAILED.requireAttachmentQueued()
            }, { fail("Rejected chunk must not retire its control") }, { retained++ })
        }
        assertEquals(1, queue.size)
        queue.single().run()
        assertEquals(1, attempts)
        assertEquals(1, retained)
    }
}
