package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttInboundBindingsTest {
    @Test fun rotationAliasesAndBrokerCopiesShareTheSignalPeerScope() {
        val bindings = MqttInboundBindings()
        bindings.replace(listOf("peer-a" to setOf("old", "now", "next"),
            "peer-a" to setOf("other-link"), "peer-b" to setOf("b")), emptySet())
        assertEquals(bindings.scope("old"), bindings.scope("now"))
        assertEquals(bindings.scope("now"), bindings.scope("other-link"))
        assertNotEquals(bindings.scope("now"), bindings.scope("b"))
        assertNull(bindings.scope("unsubscribed"))
    }

    @Test fun replacedSnapshotRemovesRevokedOrExpiredTopics() {
        val bindings = MqttInboundBindings()
        bindings.replace(listOf("a" to setOf("old")), setOf("pair"))
        bindings.replace(listOf("a" to setOf("new")), emptySet())
        assertNull(bindings.scope("old"))
        assertNull(bindings.scope("pair"))
        assertEquals("signal:a", bindings.scope("new"))
    }

    @Test fun ambiguousTopicIsNotAdmittedUnderAnArbitraryIdentity() {
        val bindings = MqttInboundBindings()
        bindings.replace(listOf("a" to setOf("collision", "a"), "b" to setOf("collision", "b")), emptySet())
        assertNull(bindings.scope("collision"))
        assertNotNull(bindings.scope("a"))
        assertNotNull(bindings.scope("b"))
    }

    @Test fun pairingAndBusinessTopicCollisionFailsClosed() {
        val bindings = MqttInboundBindings()
        bindings.replace(listOf("a" to setOf("collision")), setOf("collision", "pair"))
        assertNull(bindings.scope("collision"))
        assertEquals("pair:pair", bindings.scope("pair"))
    }

    @Test fun onlyConfiguredExactTopicsAreAccepted() {
        val bindings = MqttInboundBindings()
        listOf("", "a/#", "a/+").forEach {
            assertThrows(IllegalArgumentException::class.java) { bindings.replace(listOf("a" to setOf(it)), emptySet()) }
        }
        assertNull(bindings.scope("a"))
    }
}
