package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRemoteSilencePolicyTest {
    @Test fun shortDisconnectDoesNotExpire() {
        assertFalse(AgentRemoteSilencePolicy.expired(1000, 0, 10, 240000))
    }
    @Test fun oldTaskRequiresFreshRecoveryAttempts() {
        val now = 94 * 3600000L
        assertFalse(AgentRemoteSilencePolicy.expired(1000, 0, 2, now))
        assertTrue(AgentRemoteSilencePolicy.expired(1000, 0, 3, now))
    }
    @Test fun authenticatedResponseRenewsLongRunningTask() {
        val now = 94 * 3600000L
        assertFalse(AgentRemoteSilencePolicy.expired(1000, now - 10000, 9, now))
        assertTrue(AgentRemoteSilencePolicy.expired(1000, now - 300000, 3, now))
    }
    @Test fun clockRollbackDoesNotExpireTask() {
        assertFalse(AgentRemoteSilencePolicy.expired(2000, 0, 3, 1000))
    }
    @Test fun mutatingActionsCannotBeReplayedOnSilence() {
        val action = AgentAction("test", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.MEDIUM,
            AgentActionStatus.WAITING_RESPONSE, "modify files")
        assertFalse(AgentRemoteSilencePolicy.permitsReplay(action, "modify files and push changes"))
        assertFalse(AgentRemoteSilencePolicy.permitsReplay(null, "hello"))
        assertFalse(AgentRemoteSilencePolicy.permitsReplay(action.copy(risk = AgentRisk.LOW), "send an email?"))
        assertTrue(AgentRemoteSilencePolicy.permitsReplay(action.copy(risk = AgentRisk.LOW), "珠海今天的天气？"))
    }
}
