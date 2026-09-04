package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GalaxySSIDeviceIdentityNameTest {
    @Test
    fun formatsDeviceNameWithIdentitySuffix() {
        assertEquals(
            "Galaxy S20 Ultra 5G · 69D7",
            GalaxySSIDeviceIdentityName.format(
                "Galaxy S20 Ultra 5G",
                "galaxyssi:0123456789ab69d7"
            )
        )
    }

    @Test
    fun normalizesWhitespaceAndUppercasesSuffix() {
        assertEquals(
            "Galaxy S26 Ultra · CDEF",
            GalaxySSIDeviceIdentityName.format(
                "  Galaxy   S26 Ultra  ",
                "galaxyssi:0123456789abcdef"
            )
        )
    }

    @Test
    fun recognizesOnlyLegacyDefaultNames() {
        assertTrue(GalaxySSIDeviceIdentityName.isLegacyDefault("Me"))
        assertTrue(GalaxySSIDeviceIdentityName.isLegacyDefault("我"))
        assertTrue(GalaxySSIDeviceIdentityName.isLegacyDefault("  "))
        assertFalse(GalaxySSIDeviceIdentityName.isLegacyDefault("Helen"))
    }
}
