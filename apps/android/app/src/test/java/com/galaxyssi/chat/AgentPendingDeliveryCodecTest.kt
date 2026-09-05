package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPendingDeliveryCodecTest {
    @Test fun unicodeAndRecoveryIdentityRoundTrip() {
        val value = AgentPendingDelivery(42, "\u4f1a\u8bdd", "turn", "task", "contact", 43)
        assertEquals(value, AgentPendingDeliveryCodec.decode(AgentPendingDeliveryCodec.encode(value), 42))
    }
    @Test fun sourceMismatchIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            AgentPendingDeliveryCodec.decode(AgentPendingDeliveryCodec.encode(value()), 43)
        }
    }
    @Test fun blankScopeIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            AgentPendingDeliveryCodec.decode(AgentPendingDeliveryCodec.encode(value().copy(turnId = " ")), 42)
        }
    }
    @Test fun legacyAbsentTaskUsesTurn() {
        val encoded = org.json.JSONObject(AgentPendingDeliveryCodec.encode(value())).also { it.remove("task_id") }
        assertEquals("turn", AgentPendingDeliveryCodec.decode(encoded.toString(), 42).taskId)
    }
    @Test fun delimiterCollisionsHaveDifferentOpaqueKeys() {
        assertNotEquals(AgentPendingDeliveryCodec.turnKey("a:b", "c"), AgentPendingDeliveryCodec.turnKey("a", "b:c"))
    }
    @Test fun turnIdentityDoesNotSilentlyTrim() {
        assertNotEquals(AgentPendingDeliveryCodec.turnKey(" a", "b"), AgentPendingDeliveryCodec.turnKey("a", "b"))
        assertFalse(AgentPendingDeliveryCodec.sameTurn(value(), "conversation", "other"))
    }
    private fun value() = AgentPendingDelivery(42, "conversation", "turn", "task", "contact")
}
