package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class QnnRuntimeResourceArbiterTest {
    @Test
    fun `latest ASR runtime owns the QNN priority lease`() {
        val arbiter = QnnRuntimeResourceArbiter()
        var firstReady = true
        var secondReady = true
        val first = arbiter.registerAsr { firstReady }
        val second = arbiter.registerAsr { secondReady }

        assertEquals(true, arbiter.asrHasPriority())
        first.close()
        secondReady = false
        assertEquals(false, arbiter.asrHasPriority())
        second.close()
        assertEquals(false, arbiter.asrHasPriority())
        firstReady = false
    }
}
