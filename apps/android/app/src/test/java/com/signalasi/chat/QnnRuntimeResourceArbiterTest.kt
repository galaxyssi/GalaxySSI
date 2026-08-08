package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class QnnRuntimeResourceArbiterTest {
    @Test
    fun `latest ASR runtime owns the release callback`() {
        val arbiter = QnnRuntimeResourceArbiter()
        var firstCalls = 0
        var secondCalls = 0
        val first = arbiter.registerAsr { firstCalls += 1 }
        val second = arbiter.registerAsr { secondCalls += 1 }

        arbiter.releaseAsrForLocalModel()
        first.close()
        arbiter.releaseAsrForLocalModel()
        second.close()
        arbiter.releaseAsrForLocalModel()

        assertEquals(0, firstCalls)
        assertEquals(2, secondCalls)
    }
}
