package com.signalasi.chat

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentEncryptedPreferenceCacheTest {
    @After
    fun tearDown() {
        AgentEncryptedPreferenceCache.clearForTest()
    }

    @Test
    fun returnsPlaintextOnlyForTheMatchingEncryptedValue() {
        AgentEncryptedPreferenceCache.put("prefs\u0000contacts", "cipher-one", "plain-one")

        assertEquals(
            "plain-one",
            AgentEncryptedPreferenceCache.get("prefs\u0000contacts", "cipher-one")
        )
        assertNull(AgentEncryptedPreferenceCache.get("prefs\u0000contacts", "cipher-two"))
    }

    @Test
    fun clearingOneNamespaceKeepsOtherPreferenceCaches() {
        AgentEncryptedPreferenceCache.put("contacts\u0000items", "cipher-a", "plain-a")
        AgentEncryptedPreferenceCache.put("sessions\u0000items", "cipher-b", "plain-b")

        AgentEncryptedPreferenceCache.clearNamespace("contacts")

        assertNull(AgentEncryptedPreferenceCache.get("contacts\u0000items", "cipher-a"))
        assertEquals(
            "plain-b",
            AgentEncryptedPreferenceCache.get("sessions\u0000items", "cipher-b")
        )
    }

    @Test
    fun expiresPlaintextAfterShortTtl() {
        var now = 1L
        AgentEncryptedPreferenceCache.setClockForTest { now }
        AgentEncryptedPreferenceCache.put("prefs\u0000secret", "cipher", "plain")

        now += AgentEncryptedPreferenceCache.CACHE_TTL_NANOS

        assertNull(AgentEncryptedPreferenceCache.get("prefs\u0000secret", "cipher"))
        assertEquals(0, AgentEncryptedPreferenceCache.sizeForTest())
    }

    @Test
    fun clearingAllRemovesEveryCachedPlaintext() {
        AgentEncryptedPreferenceCache.put("one\u0000secret", "cipher-a", "plain-a")
        AgentEncryptedPreferenceCache.put("two\u0000secret", "cipher-b", "plain-b")

        AgentEncryptedPreferenceCache.clearAll()

        assertEquals(0, AgentEncryptedPreferenceCache.sizeForTest())
    }
}
