package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class MessageRowSnapshotFactoryTest {
    private val contact = Contact("phone:test", "Test phone", "")

    @Test
    fun `delivery metadata changes do not invalidate a visible message row`() {
        val message = message(id = 1L, content = "hello")
        val before = MessageRowSnapshotFactory.from(listOf(message)).single()

        message.deliveryStatus = "delivered"
        message.deliveryTrace += DeliveryTraceEvent("broker_ack")
        message.taskStatus = "completed"

        assertEquals(before, MessageRowSnapshotFactory.from(listOf(message)).single())
    }

    @Test
    fun `attachment progress changes invalidate only its message row`() {
        val first = message(
            id = 1L,
            content = "",
            attachments = listOf(PeerChatAttachment("one.jpg", "image/jpeg", 128L))
        )
        val second = message(id = 2L, content = "unchanged")
        val before = MessageRowSnapshotFactory.from(listOf(first, second))

        first.attachments = first.attachments.map {
            it.copy(transferProgress = 50, transferState = "uploading")
        }
        val after = MessageRowSnapshotFactory.from(listOf(first, second))

        assertNotEquals(before[0], after[0])
        assertEquals(before[1], after[1])
    }

    @Test
    fun `adding a message preserves existing row snapshots`() {
        val first = message(id = 1L, content = "image")
        val before = MessageRowSnapshotFactory.from(listOf(first))
        val after = MessageRowSnapshotFactory.from(
            listOf(first, message(id = 2L, content = "new message"))
        )

        assertEquals(before.single(), after.first())
    }

    @Test
    fun `adapter list snapshot is isolated from structural source mutations`() {
        val source = mutableListOf(message(id = 1L, content = "first"))
        val snapshot = MessageListSnapshot.copy(source)

        source.add(message(id = 2L, content = "second"))

        assertEquals(listOf(1L), snapshot.map(ChatMessage::id))
        assertEquals(listOf(1L, 2L), source.map(ChatMessage::id))
    }

    private fun message(
        id: Long,
        content: String,
        attachments: List<PeerChatAttachment> = emptyList()
    ) = ChatMessage(
        id = id,
        content = content,
        isMine = true,
        contact = contact,
        timestamp = 1_000L + id,
        attachments = attachments
    )
}
