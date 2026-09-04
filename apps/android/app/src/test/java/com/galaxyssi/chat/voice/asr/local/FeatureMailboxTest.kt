package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import java.nio.ByteBuffer

class FeatureMailboxTest {
    @Test
    fun newerPartialReplacesOlderPendingPartial() {
        val mailbox = FeatureMailbox()
        val first = packet(NativeFeatureWindowKind.PARTIAL, 1L)
        val second = packet(NativeFeatureWindowKind.PARTIAL, 2L)

        assertEquals(emptyList<FeaturePacket>(), mailbox.offer(first))
        assertEquals(listOf(first), mailbox.offer(second))
        assertSame(second, mailbox.take())
        mailbox.close()
    }

    @Test
    fun finalSupersedesPendingPartialAndCannotBeReplaced() {
        val mailbox = FeatureMailbox()
        val partial = packet(NativeFeatureWindowKind.PARTIAL, 1L)
        val final = packet(NativeFeatureWindowKind.FINAL, 2L)
        val latePartial = packet(NativeFeatureWindowKind.PARTIAL, 3L)

        mailbox.offer(partial)
        assertEquals(listOf(partial), mailbox.offer(final))
        assertEquals(listOf(latePartial), mailbox.offer(latePartial))
        assertSame(final, mailbox.take())
        assertEquals(emptyList<FeaturePacket>(), mailbox.close())
        assertNull(mailbox.take())
    }

    private fun packet(kind: NativeFeatureWindowKind, end: Long) = FeaturePacket(
        NativeFeatureWindow(kind, 0L, end, 0L, 0),
        ByteBuffer.allocateDirect(4)
    )
}
