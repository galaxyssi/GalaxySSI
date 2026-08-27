package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneRelationshipIdentityBindingTest {
    private val firstFingerprint = "1".repeat(64)
    private val secondFingerprint = "2".repeat(64)

    @Test
    fun bothIdentityDirectionsDeriveTheSameTransportMaterial() {
        val sharedSecret = ByteArray(32) { it.toByte() }

        val first = PhoneRelationshipIdentityBinding.deriveLinkSecret(
            sharedSecret,
            firstFingerprint,
            secondFingerprint
        )
        val second = PhoneRelationshipIdentityBinding.deriveLinkSecret(
            sharedSecret,
            secondFingerprint,
            firstFingerprint
        )
        val firstRoute = PhoneRelationshipIdentityBinding.deriveRouteId(
            first,
            firstFingerprint,
            secondFingerprint
        )
        val secondRoute = PhoneRelationshipIdentityBinding.deriveRouteId(
            second,
            secondFingerprint,
            firstFingerprint
        )

        assertEquals(first, second)
        assertEquals(firstRoute, secondRoute)
        assertTrue(SignalASILinkProtocol.validLinkSecret(first))
        assertTrue(SignalASILinkProtocol.validRouteId(firstRoute))
    }

    @Test
    fun differentSignalAgreementProducesDifferentRelationship() {
        val first = PhoneRelationshipIdentityBinding.deriveLinkSecret(
            ByteArray(32) { 3 },
            firstFingerprint,
            secondFingerprint
        )
        val second = PhoneRelationshipIdentityBinding.deriveLinkSecret(
            ByteArray(32) { 4 },
            firstFingerprint,
            secondFingerprint
        )

        assertNotEquals(first, second)
    }
}
