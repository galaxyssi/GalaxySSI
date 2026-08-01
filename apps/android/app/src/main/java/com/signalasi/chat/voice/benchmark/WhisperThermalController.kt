package com.signalasi.chat.voice.benchmark

import android.os.PowerManager
import android.os.SystemClock

class WhisperThermalController(
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime
) {
    private var heldStatus = PowerManager.THERMAL_STATUS_NONE
    private var releaseAtElapsedMs = 0L

    @Synchronized
    fun effectiveStatus(observedStatus: Int): Int {
        val observed = observedStatus.coerceIn(
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_SHUTDOWN
        )
        val now = elapsedRealtime()
        if (observed >= PowerManager.THERMAL_STATUS_MODERATE) {
            if (observed >= heldStatus || now >= releaseAtElapsedMs) {
                heldStatus = observed
                releaseAtElapsedMs = now + cooldownMs(observed)
            }
            return maxOf(observed, heldStatus)
        }
        if (now < releaseAtElapsedMs) return heldStatus
        heldStatus = PowerManager.THERMAL_STATUS_NONE
        releaseAtElapsedMs = 0L
        return observed
    }

    @Synchronized
    fun remainingCooldownMs(): Long = (releaseAtElapsedMs - elapsedRealtime()).coerceAtLeast(0L)

    private fun cooldownMs(status: Int): Long = when {
        status >= PowerManager.THERMAL_STATUS_CRITICAL -> 180_000L
        status >= PowerManager.THERMAL_STATUS_SEVERE -> 90_000L
        else -> 30_000L
    }
}
