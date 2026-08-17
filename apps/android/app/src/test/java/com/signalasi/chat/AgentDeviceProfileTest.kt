package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDeviceProfileTest {
    @Test
    fun automotiveProfileIsVoiceFirstAndConservative() {
        val profile = AgentDeviceProfilePolicy.resolve(signals(automotive = true))

        assertEquals(AgentDeviceProfileKind.AUTOMOTIVE, profile.kind)
        assertTrue(profile.voiceFirst)
        assertTrue(profile.reduceMotion)
        assertEquals(1, profile.maxTeamConcurrency)
        assertEquals(64, profile.minimumTouchTargetDp)
    }

    @Test
    fun tabletProfileExpandsSafeParallelismAndCaptureSize() {
        val profile = AgentDeviceProfilePolicy.resolve(signals(smallestWidthDp = 800))

        assertEquals(AgentDeviceProfileKind.TABLET, profile.kind)
        assertEquals(4, profile.maxTeamConcurrency)
        assertEquals(6, profile.maxQemuCpuCount)
        assertEquals(2_048, profile.maxScreenCaptureLongEdgePx)
        assertFalse(profile.conservativeMedia)
    }

    @Test
    fun oldSamsungPhoneUsesCompatibilityBudget() {
        val profile = AgentDeviceProfilePolicy.resolve(
            signals(manufacturer = "Samsung", sdkInt = 29)
        )

        assertEquals(AgentDeviceProfileKind.LEGACY_SAMSUNG_PHONE, profile.kind)
        assertEquals(1, profile.maxReadReasoningTasks)
        assertEquals(640, profile.maxQemuMemoryMegabytes)
        assertTrue(profile.conservativeMedia)
    }

    @Test
    fun lowMemorySamsungTabletKeepsBothCompatibilityAndTabletIdentity() {
        val profile = AgentDeviceProfilePolicy.resolve(
            signals(
                manufacturer = "samsung",
                sdkInt = 34,
                smallestWidthDp = 720,
                lowRam = true
            )
        )

        assertEquals(AgentDeviceProfileKind.LEGACY_SAMSUNG_TABLET, profile.kind)
        assertEquals(2, profile.maxTeamConcurrency)
        assertEquals(52, profile.minimumTouchTargetDp)
    }

    @Test
    fun currentSamsungPhoneIsNotMisclassifiedAsLegacy() {
        val profile = AgentDeviceProfilePolicy.resolve(
            signals(
                manufacturer = "samsung",
                sdkInt = 34,
                totalRamBytes = 8L * 1024L * 1024L * 1024L
            )
        )

        assertEquals(AgentDeviceProfileKind.PHONE, profile.kind)
        assertEquals(6, profile.maxQemuCpuCount)
    }

    @Test
    fun genericOldPhoneIsNotGivenSamsungSpecificWorkarounds() {
        val profile = AgentDeviceProfilePolicy.resolve(
            signals(manufacturer = "other", sdkInt = 28, lowRam = true)
        )

        assertEquals(AgentDeviceProfileKind.PHONE, profile.kind)
    }

    @Test
    fun largeTabletCaptureIsDownscaledWithoutChangingAspectRatio() {
        val profile = AgentDeviceProfilePolicy.resolve(signals(smallestWidthDp = 700))

        assertEquals(1_280 to 2_048, profile.constrainCaptureSize(1_600, 2_560))
    }

    @Test
    fun conservativeDeviceCapsNormalMediaWithoutChangingDeferredState() {
        val profile = AgentDeviceProfilePolicy.resolve(
            signals(manufacturer = "samsung", sdkInt = 29)
        )
        val adapted = profile.adaptMedia(
            AgentMediaDeliveryProfile(
                state = AgentMediaNetworkState.NORMAL,
                id = "normal",
                imageTargetBytes = 100_000,
                audioSampleRateHz = 44_100,
                audioBitRateBps = 96_000,
                deferMediaUpload = false
            )
        )

        assertEquals(64 * 1024, adapted.imageTargetBytes)
        assertEquals(16_000, adapted.audioSampleRateHz)
        assertEquals(32_000, adapted.audioBitRateBps)
        assertFalse(adapted.deferMediaUpload)
    }

    private fun signals(
        manufacturer: String = "other",
        sdkInt: Int = 34,
        smallestWidthDp: Int = 411,
        automotive: Boolean = false,
        lowRam: Boolean = false,
        totalRamBytes: Long = 8L * 1024L * 1024L * 1024L
    ) = AgentDeviceProfileSignals(
        manufacturer = manufacturer,
        sdkInt = sdkInt,
        smallestScreenWidthDp = smallestWidthDp,
        automotive = automotive,
        lowRamDevice = lowRam,
        totalRamBytes = totalRamBytes
    )
}
