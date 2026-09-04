package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelDownloadProtocolTest {
    @Test
    fun validRangeResponseAppendsAtRequestedOffset() {
        assertTrue(LocalModelDownloadProtocol.shouldAppend(500L, 206, "bytes 500-999/1000"))
    }

    @Test
    fun fullResponseRestartsInsteadOfAppending() {
        assertFalse(LocalModelDownloadProtocol.shouldAppend(500L, 200, null))
    }

    @Test
    fun mismatchedRangeCannotBeAppended() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalModelDownloadProtocol.shouldAppend(500L, 206, "bytes 0-999/1000")
        }
    }

    @Test
    fun oversizedPartialRestartsAtZero() {
        assertEquals(0L, LocalModelDownloadProtocol.resumeOffset(1001L, 1000L))
        assertEquals(1000L, LocalModelDownloadProtocol.resumeOffset(1000L, 1000L))
    }
}
