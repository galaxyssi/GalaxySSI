package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SignalASIDeviceIdentityNameTest {
    @Test
    fun formatsDeviceNameWithIdentitySuffix() {
        assertEquals(
            "Galaxy S20 Ultra 5G · 69D7",
            SignalASIDeviceIdentityName.format(
                "Galaxy S20 Ultra 5G",
                "signalasi:0123456789ab69d7"
            )
        )
    }

    @Test
    fun normalizesWhitespaceAndUppercasesSuffix() {
        assertEquals(
            "Galaxy S26 Ultra · CDEF",
            SignalASIDeviceIdentityName.format(
                "  Galaxy   S26 Ultra  ",
                "signalasi:0123456789abcdef"
            )
        )
    }

    @Test
    fun recognizesOnlyLegacyDefaultNames() {
        assertTrue(SignalASIDeviceIdentityName.isLegacyDefault("Me"))
        assertTrue(SignalASIDeviceIdentityName.isLegacyDefault("我"))
        assertTrue(SignalASIDeviceIdentityName.isLegacyDefault("  "))
        assertFalse(SignalASIDeviceIdentityName.isLegacyDefault("Helen"))
    }
}
