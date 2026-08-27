package com.signalasi.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class WipingByteArrayMediaDataSourceTest {
    @Test
    fun readsRequestedRangesAndClearsOnClose() {
        val sourceBytes = byteArrayOf(10, 20, 30, 40, 50)
        val source = WipingByteArrayMediaDataSource(sourceBytes)
        val output = ByteArray(3)

        assertEquals(3, source.readAt(1, output, 0, output.size))
        assertArrayEquals(byteArrayOf(20, 30, 40), output)
        assertEquals(5L, source.size)

        source.close()

        assertArrayEquals(ByteArray(sourceBytes.size), sourceBytes)
        assertEquals(0L, source.size)
        assertEquals(-1, source.readAt(0, output, 0, output.size))
    }
}
