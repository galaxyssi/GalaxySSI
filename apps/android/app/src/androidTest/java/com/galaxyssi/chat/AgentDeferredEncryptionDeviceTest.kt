package com.galaxyssi.chat

import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

/** Uses only uniquely named test records; never clears the user's sending queue. */
class AgentDeferredEncryptionDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test fun localBackpressureDoesNotConsumeRetryBudgetOrReceiptCredit() {
        val id = UUID.randomUUID().toString()
        val route = "test-backpressure-$id"
        try {
            assertTrue(GalaxySSILinkDeliveryStore.enqueue(context, id, route, "{}"))
            repeat(20) {
                assertEquals(0L, GalaxySSILinkDeliveryStore.retryWindow.acquire(route, id))
                GalaxySSILinkDeliveryStore.markAttempt(context, id)
                GalaxySSILinkDeliveryStore.deferUnsubmittedAttempt(context, id)
            }
            Thread.sleep(1_100)
            assertEquals(0, GalaxySSILinkDeliveryStore.pending(context).single { it.messageId == id }.attempts)
            assertEquals(0L, GalaxySSILinkDeliveryStore.retryWindow.acquire(route, id))
            GalaxySSILinkDeliveryStore.markAttempt(context, id)
            GalaxySSILinkDeliveryStore.markPublished(context, id)
            GalaxySSILinkDeliveryStore.deferUnsubmittedAttempt(context, id)
            assertTrue(GalaxySSILinkDeliveryStore.retryWindow.acquire(route, id) > 1_000L)
        } finally { GalaxySSILinkDeliveryStore.discard(context, id) }
    }

    @Test fun waitsForEveryAttachmentThenCommitsOneCiphertextForRetries() {
        val id = UUID.randomUUID().toString()
        val a = UUID.randomUUID().toString().replace("-", "").repeat(2)
        val b = UUID.randomUUID().toString().replace("-", "").repeat(2)
        val envelope = JSONObject().put("message_id", id).put("payload", JSONObject().put("task_id", "fixture"))
        var encryptions = 0
        try {
            assertTrue(GalaxySSILinkDeliveryStore.enqueue(context, id, "test-deferred-$id", "{}",
                blockedByAttachmentTransferIds = listOf(a, b), recoverableEnvelope = envelope.toString(),
                deferredSignalEncryption = true))
            assertFalse(GalaxySSILinkDeliveryStore.pending(context).any { it.messageId == id })
            assertEquals(0, GalaxySSILinkDeliveryStore.releaseAttachmentDependency(context, a))
            assertFalse(GalaxySSILinkDeliveryStore.pending(context).any { it.messageId == id })
            assertEquals(1, GalaxySSILinkDeliveryStore.releaseAttachmentDependency(context, b))
            val ready = GalaxySSILinkDeliveryStore.pending(context).single { it.messageId == id }
            assertTrue(ready.deferredSignalEncryption)
            assertNull(GalaxySSILinkDeliveryStore.prepareFirstSend(context, ready) { null })
            val sealed = requireNotNull(GalaxySSILinkDeliveryStore.prepareFirstSend(context, ready) {
                encryptions++
                assertEquals(envelope.toString(), it.toString())
                JSONObject().put("scheme", "signal").put("body", "ciphertext-fixture")
                    .put("from", "fixture-phone").put("to", "fixture-desktop")
            })
            assertFalse(sealed.deferredSignalEncryption)
            val retry = GalaxySSILinkDeliveryStore.pending(context).single { it.messageId == id }
            assertEquals(sealed.wirePayload, retry.wirePayload)
            assertEquals(sealed.wirePayload, GalaxySSILinkDeliveryStore.prepareFirstSend(context, retry) {
                fail("A retry must reuse the committed ciphertext"); null
            }?.wirePayload)
            assertEquals(1, encryptions)
        } finally { GalaxySSILinkDeliveryStore.discard(context, id) }
    }

    @Test fun missingOrDiscardedEnvelopeCannotPublishPlaceholder() {
        val id = UUID.randomUUID().toString()
        val transfer = "c".repeat(64)
        try {
            GalaxySSILinkDeliveryStore.enqueue(context, id, "test-deferred-$id", "{}",
                blockedByAttachmentTransferIds = listOf(transfer), recoverableEnvelope = "invalid",
                deferredSignalEncryption = true)
            GalaxySSILinkDeliveryStore.releaseAttachmentDependency(context, transfer)
            val ready = GalaxySSILinkDeliveryStore.pending(context).single { it.messageId == id }
            assertNull(GalaxySSILinkDeliveryStore.prepareFirstSend(context, ready) { fail("Invalid input"); null })
            GalaxySSILinkDeliveryStore.discard(context, id)
            assertNull(GalaxySSILinkDeliveryStore.prepareFirstSend(context, ready) { fail("Cancelled input"); null })
        } finally { GalaxySSILinkDeliveryStore.discard(context, id) }
    }
}
