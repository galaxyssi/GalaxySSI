package com.galaxyssi.chat.voice.model

import java.util.Locale

enum class WhisperNetworkClass {
    WIFI,
    UNMETERED,
    METERED,
    OFFLINE,
    UNKNOWN
}

enum class WhisperDownloadDecision {
    ALLOW,
    REQUIRE_METERED_CONFIRMATION,
    WAIT_FOR_NETWORK,
    INSUFFICIENT_SPACE
}

data class WhisperDownloadPolicyResult(
    val decision: WhisperDownloadDecision,
    val requiredFreeBytes: Long,
    val availableFreeBytes: Long
)

object WhisperModelDownloadPolicy {
    fun evaluate(
        profile: WhisperModelProfile,
        network: WhisperNetworkClass,
        availableFreeBytes: Long,
        @Suppress("UNUSED_PARAMETER") meteredConfirmed: Boolean = false
    ): WhisperDownloadPolicyResult {
        val required = safeAdd(safeMultiply(profile.expectedSizeBytes, 2L), profile.minFreeStorageBytes)
        val decision = when {
            availableFreeBytes in 0 until required -> WhisperDownloadDecision.INSUFFICIENT_SPACE
            network == WhisperNetworkClass.OFFLINE -> WhisperDownloadDecision.WAIT_FOR_NETWORK
            else -> WhisperDownloadDecision.ALLOW
        }
        return WhisperDownloadPolicyResult(decision, required, availableFreeBytes)
    }

    fun orderedSources(profile: WhisperModelProfile, locale: Locale): List<String> {
        val preferChinaMirror = locale.language.equals("zh", ignoreCase = true)
        return profile.sourceUrls.sortedBy { url ->
            when {
                preferChinaMirror && url.contains("hf-mirror.com") -> 0
                !preferChinaMirror && url.contains("huggingface.co") -> 0
                else -> 1
            }
        }
    }

    fun requiresUnmetered(profile: WhisperModelProfile): Boolean = profile.family in setOf(
        WhisperModelFamily.MEDIUM,
        WhisperModelFamily.LARGE_V3,
        WhisperModelFamily.LARGE_V3_TURBO
    )

    private fun safeMultiply(value: Long, multiplier: Long): Long = runCatching {
        Math.multiplyExact(value, multiplier)
    }.getOrDefault(Long.MAX_VALUE)

    private fun safeAdd(left: Long, right: Long): Long = runCatching {
        Math.addExact(left, right)
    }.getOrDefault(Long.MAX_VALUE)
}
