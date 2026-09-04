package com.galaxyssi.chat.voice.model

data class WhisperMemoryAdmissionDecision(
    val allowed: Boolean,
    val requiredHeadroomBytes: Long,
    val availableHeadroomBytes: Long,
    val lowMemory: Boolean
)

object WhisperMemoryAdmissionPolicy {
    const val SAFETY_MARGIN_BYTES = 256L * 1024L * 1024L

    fun estimatedIncrementalBytes(
        profile: WhisperModelProfile,
        currentPssBytes: Long = 0L,
        certifiedPeakPssBytes: Long = 0L,
        alreadyLoaded: Boolean = false
    ): Long {
        if (alreadyLoaded) return 0L
        val measuredIncrement = (certifiedPeakPssBytes - currentPssBytes).coerceAtLeast(0L)
        return maxOf(profile.expectedSizeBytes, measuredIncrement)
    }

    fun evaluate(
        profile: WhisperModelProfile,
        availableMemoryBytes: Long,
        currentPssBytes: Long = 0L,
        certifiedPeakPssBytes: Long = 0L,
        alreadyLoaded: Boolean = false,
        lowMemory: Boolean = false,
        safetyMarginBytes: Long = SAFETY_MARGIN_BYTES
    ): WhisperMemoryAdmissionDecision {
        val incremental = estimatedIncrementalBytes(
            profile = profile,
            currentPssBytes = currentPssBytes,
            certifiedPeakPssBytes = certifiedPeakPssBytes,
            alreadyLoaded = alreadyLoaded
        )
        val required = saturatedAdd(incremental, safetyMarginBytes.coerceAtLeast(0L))
        val available = availableMemoryBytes.coerceAtLeast(0L)
        return WhisperMemoryAdmissionDecision(
            allowed = !lowMemory && required <= available,
            requiredHeadroomBytes = required,
            availableHeadroomBytes = available,
            lowMemory = lowMemory
        )
    }

    private fun saturatedAdd(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right
}
