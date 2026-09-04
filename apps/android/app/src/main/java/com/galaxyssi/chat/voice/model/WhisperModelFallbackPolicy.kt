package com.galaxyssi.chat.voice.model

object WhisperModelFallbackPolicy {
    private const val REALTIME_RESCUE_MAX_BYTES = 256L * 1024L * 1024L

    fun select(
        requested: WhisperModelProfile,
        installedProfiles: List<WhisperModelProfile>,
        canRun: (WhisperModelProfile) -> Boolean
    ): WhisperModelProfile? = candidates(requested, installedProfiles).firstOrNull(canRun)

    fun candidates(
        requested: WhisperModelProfile,
        installedProfiles: List<WhisperModelProfile>
    ): List<WhisperModelProfile> = installedProfiles
        .asSequence()
        .filter { candidate ->
            candidate.id != requested.id &&
                candidate.expectedSizeBytes < requested.expectedSizeBytes
        }
        .distinctBy(WhisperModelProfile::id)
        .sortedWith(
            compareByDescending<WhisperModelProfile> { it.family == requested.family }
                .thenByDescending { qualityRank(it.family) }
                .thenByDescending { quantizationRank(it.quantization) }
                .thenByDescending(WhisperModelProfile::expectedSizeBytes)
        )
        .toList()

    fun selectRealtimeRescue(
        installedProfiles: List<WhisperModelProfile>,
        canRun: (WhisperModelProfile) -> Boolean
    ): WhisperModelProfile? = installedProfiles
        .asSequence()
        .filter { candidate ->
            candidate.expectedSizeBytes <= REALTIME_RESCUE_MAX_BYTES &&
                candidate.recommendedMode == WhisperExecutionMode.REALTIME_PARTIAL
        }
        .distinctBy(WhisperModelProfile::id)
        .sortedWith(
            compareBy<WhisperModelProfile>(WhisperModelProfile::expectedSizeBytes)
                .thenBy { it.id }
        )
        .firstOrNull(canRun)

    private fun qualityRank(family: WhisperModelFamily): Int = when (family) {
        WhisperModelFamily.TINY -> 1
        WhisperModelFamily.BASE -> 2
        WhisperModelFamily.SMALL -> 3
        WhisperModelFamily.MEDIUM -> 4
        WhisperModelFamily.LARGE_V3_TURBO -> 5
        WhisperModelFamily.LARGE_V3 -> 6
    }

    private fun quantizationRank(quantization: WhisperQuantization): Int = when (quantization) {
        WhisperQuantization.F32 -> 8
        WhisperQuantization.F16 -> 7
        WhisperQuantization.Q8_0 -> 6
        WhisperQuantization.Q6_K -> 5
        WhisperQuantization.Q5_1 -> 4
        WhisperQuantization.Q5_0 -> 3
        WhisperQuantization.Q4_1 -> 2
        WhisperQuantization.Q4_0 -> 1
        WhisperQuantization.UNKNOWN -> 0
    }
}
