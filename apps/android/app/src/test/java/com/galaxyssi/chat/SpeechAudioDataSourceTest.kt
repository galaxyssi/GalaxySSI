package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class SpeechAudioDataSourceTest {
    @Test fun supportsRandomReadsAndEndOfInput() {
        val bytes = byteArrayOf(1, 2, 3, 4)
        val source = SpeechAudioDataSource(bytes)
        val output = ByteArray(5)
        assertEquals(4L, source.size)
        assertEquals(2, source.readAt(2, output, 1, 4))
        assertArrayEquals(byteArrayOf(0, 3, 4, 0, 0), output)
        assertEquals(-1, source.readAt(4, output, 0, 1))
        assertEquals(-1, source.readAt(Long.MAX_VALUE, output, 0, 1))
        assertEquals(-1, source.readAt(-1, output, 0, 1))
        assertEquals(0, source.readAt(4, output, 0, 0))
    }

    @Test fun closingErasesAudioAndIsIdempotent() {
        val bytes = ByteArray(100) { 12 }
        val source = SpeechAudioDataSource(bytes)
        source.close(); source.close()
        assertArrayEquals(ByteArray(100), bytes)
        assertEquals(0L, source.size)
        assertEquals(-1, source.readAt(0, ByteArray(2), 0, 2))
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsInvalidDestinationRange() {
        SpeechAudioDataSource(byteArrayOf(1)).readAt(0, ByteArray(2), 2, 1)
    }
}
