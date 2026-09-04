package com.galaxyssi.chat.voice.benchmark

import android.os.SystemClock
import com.galaxyssi.chat.voice.reliability.VoiceThermalController

class WhisperThermalController(
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime
) {
    private val delegate = VoiceThermalController(elapsedRealtime)

    fun effectiveStatus(observedStatus: Int): Int = delegate.evaluate(observedStatus).effectiveStatus

    fun remainingCooldownMs(): Long = delegate.remainingCooldownMs()

    fun reset() = delegate.reset()
}
