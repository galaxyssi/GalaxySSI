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
            "signalasichat/v1/server/client/up",
            wirePayload
        )

        val pending = SignalASILinkDeliveryStore.pending(context)
        val directory = File(context.filesDir, "signalasi-link-outbox-v1")
        val preferences = context.getSharedPreferences(
            "signalasi_link_delivery_v1",
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
            "signalasichat/v1/server/client/up",
            "encrypted-task",
            blockedByAttachmentTransferIds = listOf(first, second)
        )

        assertTrue(SignalASILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(0, SignalASILinkDeliveryStore.releaseAttachmentDependency(context, first))
        assertTrue(SignalASILinkDeliveryStore.pending(context).isEmpty())
        assertEquals(1, SignalASILinkDeliveryStore.releaseAttachmentDependency(context, second))
        assertEquals("encrypted-task", SignalASILinkDeliveryStore.pending(context).single().wirePayload)
    }
}
