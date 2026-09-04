package com.galaxyssi.chat.voice.benchmark

import android.os.PowerManager
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class WhisperThermalControllerTest {
    @Test
    fun severePressureRemainsHeldUntilCooldownExpires() {
        val clock = AtomicLong(1_000L)
        val controller = WhisperThermalController(clock::get)

        assertEquals(
            PowerManager.THERMAL_STATUS_SEVERE,
            controller.effectiveStatus(PowerManager.THERMAL_STATUS_SEVERE)
        )
        clock.addAndGet(89_999L)
        assertEquals(
            PowerManager.THERMAL_STATUS_SEVERE,
            controller.effectiveStatus(PowerManager.THERMAL_STATUS_NONE)
        )
        clock.incrementAndGet()
        assertEquals(
            PowerManager.THERMAL_STATUS_NONE,
            controller.effectiveStatus(PowerManager.THERMAL_STATUS_NONE)
        )
    }

    @Test
    fun lowerObservedPressureDoesNotShortenAnActiveCriticalCooldown() {
        val clock = AtomicLong(5_000L)
        val controller = WhisperThermalController(clock::get)

        controller.effectiveStatus(PowerManager.THERMAL_STATUS_CRITICAL)
        clock.addAndGet(60_000L)

        assertEquals(
            PowerManager.THERMAL_STATUS_CRITICAL,
            controller.effectiveStatus(PowerManager.THERMAL_STATUS_MODERATE)
        )
        assertEquals(120_000L, controller.remainingCooldownMs())
    }
}
