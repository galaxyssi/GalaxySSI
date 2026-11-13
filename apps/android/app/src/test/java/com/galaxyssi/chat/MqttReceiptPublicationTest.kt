package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttReceiptPublicationTest {
    private data class Result(val broker: String, var done: Boolean = false, var success: Boolean = false)
    private var now = 0L
    private val sent = mutableListOf<Result>()
    private val paths = mutableListOf("emqx", "hivemq", "mosquitto")
    private val publication = MqttReceiptPublication({ now }) { attempted ->
        paths.firstOrNull { it !in attempted }?.let { broker ->
            val result = Result(broker).also { sent.add(it) }
            MqttReceiptPublication.Attempt(broker, { result.done }, { result.done && result.success })
        }
    }

    @Test fun admissionIsNotSuccessAndAlternateWaitsForGrace() {
        assertFalse(publication.send())
        now = 999
        assertFalse(publication.send())
        assertEquals(1, sent.size)
        now = 1000
        assertFalse(publication.send())
        assertEquals(listOf("emqx", "hivemq"), sent.map { it.broker })
        sent.last().apply { done = true; success = true }
        now = 2000
        assertTrue(publication.send())
        assertEquals(2, sent.size)
    }

    @Test fun lateFirstPathSuccessStopsMoreCopies() {
        publication.send()
        now = 1000
        publication.send()
        sent.first().apply { done = true; success = true }
        now = 2000
        assertTrue(publication.send())
        assertEquals(2, sent.size)
    }

    @Test fun asyncFailureTriesAnotherPathImmediately() {
        publication.send()
        sent.first().done = true
        assertFalse(publication.send())
        assertEquals(listOf("emqx", "hivemq"), sent.map { it.broker })
    }

    @Test fun pendingCopiesRemainBounded() {
        repeat(30) { now = it * 1000L; assertFalse(publication.send()) }
        assertEquals(3, sent.size)
    }

    @Test fun failedPathsCanRetryOnALaterTick() {
        repeat(3) { assertFalse(publication.send()); sent.last().done = true }
        assertFalse(publication.send())
        assertEquals(3, sent.size)
        assertFalse(publication.send())
        assertEquals(4, sent.size)
    }

    @Test fun absentAuthorizedPathNeverReportsSuccess() {
        paths.clear()
        assertFalse(publication.send())
        assertTrue(sent.isEmpty())
        paths.add("hivemq")
        assertFalse(publication.send())
        sent.first().apply { done = true; success = true }
        assertTrue(publication.send())
    }
}
