package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorStreamHandoffTest {
    @Test
    fun finalResultIsPersistedBeforeLiveStreamIsRetired() {
        val calls = mutableListOf<String>()

        val result = AgentConnectorStreamHandoff.persistThenRetire(
            persistFinal = {
                calls += "persist"
                true
            },
            retireLiveStream = { calls += "retire" }
        )

        assertTrue(result)
        assertEquals(listOf("persist", "retire"), calls)
    }

    @Test
    fun failedPersistenceKeepsLiveStreamVisible() {
        var retired = false

        runCatching {
            AgentConnectorStreamHandoff.persistThenRetire(
                persistFinal = { error("write failed") },
                retireLiveStream = { retired = true }
            )
        }

        assertFalse(retired)
    }
}
