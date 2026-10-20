package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentCodexSilenceRecoveryTest {
    private fun next(state: Map<String, String> = emptyMap(), current: String = "codex",
        available: List<String> = listOf("deepseek", "local"), timeout: Boolean = true) =
        AgentCodexSilenceRecovery.next(state, current, current == "codex", timeout, available)!!

    @Test fun twoTimeoutsThenAlternativesThenOneFinalCodexAttempt() {
        val first = next()
        assertEquals("codex", first.resourceId)
        val second = next(first.state)
        assertEquals("deepseek", second.resourceId)
        val third = next(second.state, "deepseek", timeout = false)
        assertEquals("local", third.resourceId)
        val fourth = next(third.state, "local", timeout = false)
        assertEquals("codex", fourth.resourceId)
        assertEquals("true", fourth.state[AgentCodexSilenceRecovery.FINAL])
        assertNull(next(fourth.state).resourceId)
    }

    @Test fun noAvailableAlternativeStillHasExactlyThreeCodexAttempts() {
        val first = next(available = emptyList())
        val second = next(first.state, available = emptyList())
        assertEquals("codex", second.resourceId)
        assertNull(next(second.state, available = emptyList()).resourceId)
    }

    @Test fun restartRestoresBudgetAndDoesNotRetryFailedAlternatives() {
        val state = next(next().state).state
        val persisted = org.json.JSONObject(AgentNativeJsonCodec.stringify(state))
        val restored = persisted.keys().asSequence().associateWith { persisted.getString(it) }
        val result = next(restored, "deepseek", listOf("deepseek", "local"))
        assertEquals("local", result.resourceId)
        assertEquals("3", result.state[AgentCodexSilenceRecovery.ATTEMPT])
    }

    @Test fun nonTimeoutAndOtherProvidersDoNotStartCodexRecovery() {
        assertNull(AgentCodexSilenceRecovery.next(emptyMap(), "codex", true, false, emptyList()))
        assertNull(AgentCodexSilenceRecovery.next(emptyMap(), "deepseek", false, true, emptyList()))
        assertEquals(180_000L, AgentCodexSilenceRecovery.MAX_SILENCE_MILLIS)
    }
}
