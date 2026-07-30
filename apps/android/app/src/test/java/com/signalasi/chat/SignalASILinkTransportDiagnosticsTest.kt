package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SignalASILinkTransportDiagnosticsTest {
    @Test
    fun recordsBoundedEventsAndKeepsLifetimeCounters() {
        var now = 1_000L
        val ledger = SignalASILinkDiagnosticLedger(
            store = InMemorySignalASILinkDiagnosticStore(),
            clock = { now.also { now += 1_000L } },
            maximumEvents = 2
        )

        ledger.record(
            SignalASILinkDiagnosticKind.ENCRYPTED_REPLAY,
            endpointIdentity = "desktop-private-route",
            messageIdentity = "message-1",
            detailCode = "pre decrypt"
        )
        ledger.record(SignalASILinkDiagnosticKind.DUPLICATE_MESSAGE, messageIdentity = "message-2")
        val snapshot = ledger.record(SignalASILinkDiagnosticKind.OLD_COUNTER, messageIdentity = "message-3")

        assertEquals(3L, snapshot.totalEvents)
        assertEquals(1L, snapshot.replayCount)
        assertEquals(1L, snapshot.duplicateCount)
        assertEquals(1L, snapshot.oldCounterCount)
        assertEquals(2, snapshot.recentEvents.size)
        assertEquals(SignalASILinkDiagnosticKind.OLD_COUNTER, snapshot.recentEvents.first().kind)
    }

    @Test
    fun persistentEventsContainOnlyAnonymousReferencesAndNormalizedCodes() {
        val ledger = SignalASILinkDiagnosticLedger(
            store = InMemorySignalASILinkDiagnosticStore(),
            clock = { 1_000L }
        )

        val snapshot = ledger.record(
            SignalASILinkDiagnosticKind.DECRYPT_FAILURE,
            endpointIdentity = "signalasi:private-phone-id",
            messageIdentity = "secret-message-id",
            detailCode = "Runtime Exception: private value"
        )
        val event = snapshot.recentEvents.single()

        assertFalse(event.endpointRef.contains("private"))
        assertFalse(event.messageRef.contains("secret"))
        assertEquals(12, event.endpointRef.length)
        assertEquals(12, event.messageRef.length)
        assertEquals("runtime_exception_private_value", event.detailCode)
        assertNotEquals(event.endpointRef, event.messageRef)
    }

    @Test
    fun decryptFailuresSeparateOldCountersFromDuplicateMessages() {
        val oldCounter = IllegalStateException("Received message with old counter: 4")
        val duplicate = DuplicateMessageExceptionForTest("Duplicate message")
        val generic = IllegalArgumentException("Malformed Signal body")

        assertEquals(
            SignalASILinkDiagnosticKind.OLD_COUNTER,
            SignalASILinkTransportDiagnostics.classifyDecryptionFailure(oldCounter)
        )
        assertEquals(
            SignalASILinkDiagnosticKind.DUPLICATE_MESSAGE,
            SignalASILinkTransportDiagnostics.classifyDecryptionFailure(duplicate)
        )
        assertEquals(
            SignalASILinkDiagnosticKind.DECRYPT_FAILURE,
            SignalASILinkTransportDiagnostics.classifyDecryptionFailure(generic)
        )
    }

    @Test
    fun fragmentClassifierExposesConflictingDuplicates() {
        assertEquals(
            SignalASILinkDiagnosticKind.CHUNK_DUPLICATE,
            SignalASILinkTransportDiagnostics.classifyFragmentFailure(
                IllegalArgumentException("Conflicting MQTT chunk duplicate")
            )
        )
        assertEquals(
            SignalASILinkDiagnosticKind.FRAGMENT_REJECTED,
            SignalASILinkTransportDiagnostics.classifyFragmentFailure(
                IllegalArgumentException("MQTT chunk integrity check failed")
            )
        )
        assertTrue(
            SignalASILinkDiagnosticLedger.anonymizedReference("route").matches(Regex("[0-9a-f]{12}"))
        )
    }

    private class DuplicateMessageExceptionForTest(message: String) : RuntimeException(message)
}
