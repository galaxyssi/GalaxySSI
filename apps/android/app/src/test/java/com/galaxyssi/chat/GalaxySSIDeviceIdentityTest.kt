package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class GalaxySSIDeviceIdentityTest {
    @Test
    fun deviceAndProfileNamesRemainReadable() {
        assertEquals(
            "S26 Ultra · Helen",
            GalaxySSIDeviceIdentity.composeDisplayName(
                deviceName = "S26 Ultra",
                model = "SM-S9480",
                profileName = "Helen",
                fingerprint = "12345678"
            )
        )
    }

    @Test
    fun defaultProfileUsesStableShortFingerprint() {
        assertEquals(
            "S26 Ultra · A84C",
            GalaxySSIDeviceIdentity.composeDisplayName(
                deviceName = "S26 Ultra",
                model = "SM-S9480",
                profileName = "Me",
                fingerprint = "a84cf19d"
            )
        )
    }
}
