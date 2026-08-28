package com.signalasi.chat

import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

class SignalASILinkFileBackedOutboxTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After
    fun cleanUp() {
        SignalASILinkDeliveryStore.clear(context)
    }

    @Test
    fun largeEncryptedPayloadIsFileBackedAndRemovedAfterReceipt() {
        SignalASILinkDeliveryStore.clear(context)
        val messageId = UUID.randomUUID().toString()
        val marker = "private-wire-marker"
        val wirePayload = marker + "x".repeat(96 * 1024)

        SignalASILinkDeliveryStore.enqueue(
            context,
            messageId,
            SignalASILinkProtocol.newLinkSecret(),
            wirePayload
        )

        val pending = SignalASILinkDeliveryStore.pending(context)
        val directory = File(context.filesDir, "opaque-link-outbox-v2")
        val preferences = context.getSharedPreferences(
            "opaque_link_delivery_v2",
            android.content.Context.MODE_PRIVATE
        )
        assertEquals(wirePayload, pending.single().wirePayload)
        assertTrue(directory.listFiles().orEmpty().any { it.extension == "wire" })
        assertFalse(preferences.getString("outbox", "").orEmpty().contains(marker))

        SignalASILinkDeliveryStore.acknowledge(context, messageId)

        assertTrue(SignalASILinkDeliveryStore.pending(context).isEmpty())
        assertTrue(directory.listFiles().orEmpty().isEmpty())
    }

    @Test
    fun taskOutboxEntryIsReleasedOnlyAfterEveryAttachmentIsStored() {
        SignalASILinkDeliveryStore.clear(context)
        val first = "a".repeat(64)
        val second = "b".repeat(64)
        SignalASILinkDeliveryStore.enqueue(
            context,
            UUID.randomUUID().toString(),
            SignalASILinkProtocol.newLinkSecret(),
            "encrypted-task",
            blockedByAttachmentTransferIds = listOf(first, second)
        )

        assertTrue(SignalASILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(0, SignalASILinkDeliveryStore.releaseAttachmentDependency(context, first))
        assertTrue(SignalASILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(1, SignalASILinkDeliveryStore.releaseAttachmentDependency(context, second))
        assertEquals("encrypted-task", SignalASILinkDeliveryStore.pending(context).single().wirePayload)
    }

    @Test
    fun permanentlyRejectedEntryCanBeDiscardedWithoutRemovingFollowingMessages() {
        SignalASILinkDeliveryStore.clear(context)
        val rejectedMessageId = UUID.randomUUID().toString()
        val validMessageId = UUID.randomUUID().toString()
        val rejectedWirePayload = "x".repeat(SignalASIMqttWireChunking.MAX_REASSEMBLED_BYTES + 1)
        val validWirePayload = "encrypted-voice-message"
        SignalASILinkDeliveryStore.enqueue(
            context,
            rejectedMessageId,
            SignalASILinkProtocol.newLinkSecret(),
            rejectedWirePayload
        )
        SignalASILinkDeliveryStore.enqueue(
            context,
            validMessageId,
            SignalASILinkProtocol.newLinkSecret(),
            validWirePayload
        )

        assertEquals(
            "MQTT wire payload exceeds reassembly limit",
            SignalASIMqttWireChunking.permanentRejectionReason(
                SignalASILinkDeliveryStore.pending(context).first().wirePayload
            )
        )

        SignalASILinkDeliveryStore.discard(context, rejectedMessageId)

        val remaining = SignalASILinkDeliveryStore.pending(context)
        assertEquals(1, remaining.size)
        assertEquals(validMessageId, remaining.single().messageId)
        assertEquals(validWirePayload, remaining.single().wirePayload)
    }
}
