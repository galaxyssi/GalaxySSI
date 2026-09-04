package com.galaxyssi.chat

import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

class GalaxySSILinkFileBackedOutboxTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After
    fun cleanUp() {
        GalaxySSILinkDeliveryStore.clear(context)
    }

    @Test
    fun largeEncryptedPayloadIsFileBackedAndRemovedAfterReceipt() {
        GalaxySSILinkDeliveryStore.clear(context)
        val messageId = UUID.randomUUID().toString()
        val marker = "private-wire-marker"
        val wirePayload = marker + "x".repeat(96 * 1024)

        GalaxySSILinkDeliveryStore.enqueue(
            context,
            messageId,
            GalaxySSILinkProtocol.newLinkSecret(),
            wirePayload
        )

        val pending = GalaxySSILinkDeliveryStore.pending(context)
        val directory = File(context.filesDir, "opaque-link-outbox-v2")
        val preferences = context.getSharedPreferences(
            "opaque_link_delivery_v2",
            android.content.Context.MODE_PRIVATE
        )
        assertEquals(wirePayload, pending.single().wirePayload)
        assertTrue(directory.listFiles().orEmpty().any { it.extension == "wire" })
        assertFalse(preferences.getString("outbox", "").orEmpty().contains(marker))

        GalaxySSILinkDeliveryStore.acknowledge(context, messageId)

        assertTrue(GalaxySSILinkDeliveryStore.pending(context).isEmpty())
        assertTrue(directory.listFiles().orEmpty().isEmpty())
    }

    @Test
    fun taskOutboxEntryIsReleasedOnlyAfterEveryAttachmentIsStored() {
        GalaxySSILinkDeliveryStore.clear(context)
        val first = "a".repeat(64)
        val second = "b".repeat(64)
        GalaxySSILinkDeliveryStore.enqueue(
            context,
            UUID.randomUUID().toString(),
            GalaxySSILinkProtocol.newLinkSecret(),
            "encrypted-task",
            blockedByAttachmentTransferIds = listOf(first, second)
        )

        assertTrue(GalaxySSILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(0, GalaxySSILinkDeliveryStore.releaseAttachmentDependency(context, first))
        assertTrue(GalaxySSILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(1, GalaxySSILinkDeliveryStore.releaseAttachmentDependency(context, second))
        assertEquals("encrypted-task", GalaxySSILinkDeliveryStore.pending(context).single().wirePayload)
    }

    @Test
    fun permanentlyRejectedEntryCanBeDiscardedWithoutRemovingFollowingMessages() {
        GalaxySSILinkDeliveryStore.clear(context)
        val rejectedMessageId = UUID.randomUUID().toString()
        val validMessageId = UUID.randomUUID().toString()
        val rejectedWirePayload = "x".repeat(GalaxySSIMqttWireChunking.MAX_REASSEMBLED_BYTES + 1)
        val validWirePayload = "encrypted-voice-message"
        GalaxySSILinkDeliveryStore.enqueue(
            context,
            rejectedMessageId,
            GalaxySSILinkProtocol.newLinkSecret(),
            rejectedWirePayload
        )
        GalaxySSILinkDeliveryStore.enqueue(
            context,
            validMessageId,
            GalaxySSILinkProtocol.newLinkSecret(),
            validWirePayload
        )

        assertEquals(
            "MQTT wire payload exceeds reassembly limit",
            GalaxySSIMqttWireChunking.permanentRejectionReason(
                GalaxySSILinkDeliveryStore.pending(context).first().wirePayload
            )
        )

        GalaxySSILinkDeliveryStore.discard(context, rejectedMessageId)

        val remaining = GalaxySSILinkDeliveryStore.pending(context)
        assertEquals(1, remaining.size)
        assertEquals(validMessageId, remaining.single().messageId)
        assertEquals(validWirePayload, remaining.single().wirePayload)
    }
}
