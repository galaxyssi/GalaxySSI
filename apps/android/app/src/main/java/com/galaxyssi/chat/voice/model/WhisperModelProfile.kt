package com.galaxyssi.chat.voice.model

import java.util.Locale

enum class WhisperModelFamily {
    TINY,
    BASE,
    SMALL,
    MEDIUM,
    LARGE_V3,
    LARGE_V3_TURBO
}

enum class WhisperQuantization {
    F16,
    F32,
    Q8_0,
    Q6_K,
    Q5_1,
    Q5_0,
    Q4_1,
    Q4_0,
    UNKNOWN
}

enum class WhisperExecutionMode {
    REALTIME_PARTIAL,
    FINAL_ONLY,
    SECOND_PASS,
    REMOTE_NODE
}

enum class WhisperCertificationLevel {
    UNTESTED,
    REALTIME,
    FINAL,
    SECOND_PASS,
    REMOTE_RECOMMENDED,
    UNSUPPORTED
}

data class WhisperModelProfile(
    val id: String,
    val family: WhisperModelFamily,
    val displayName: String,
    val fileName: String,
    val sourceUrls: List<String>,
    val expectedSizeBytes: Long,
    val sha256: String,
    val quantization: WhisperQuantization,
    val multilingual: Boolean,
    val recommendedMode: WhisperExecutionMode,
    val minAvailableRamBytes: Long,
    val minFreeStorageBytes: Long,
    val defaultPartialIntervalMs: Long,
    val maxWindowMs: Long,
    val enabledByDefault: Boolean,
    val experimental: Boolean,
    val manifestVersion: Int,
    val bundledAsset: Boolean = false,
    val legacyIds: Set<String> = emptySet()
) {
    init {
        require(ID_PATTERN.matches(id)) { "Invalid model profile id" }
        require(displayName.isNotBlank()) { "Model display name is required" }
        require(FILE_PATTERN.matches(fileName)) { "Invalid model file name" }
        require(sourceUrls.isNotEmpty() || bundledAsset) { "At least one model source is required" }
        require(sourceUrls.all { it.startsWith("https://") }) { "Model sources must use HTTPS" }
        require(expectedSizeBytes > 0L) { "Expected model size must be positive" }
        require(SHA_PATTERN.matches(sha256)) { "Model SHA-256 must be lowercase hexadecimal" }
        require(minAvailableRamBytes >= 0L && minFreeStorageBytes >= 0L)
        require(defaultPartialIntervalMs > 0L && maxWindowMs > 0L)
        require(manifestVersion > 0)
        require(legacyIds.all(ID_PATTERN::matches))
    }

    val bundled: Boolean
        get() = bundledAsset

    val sizeLabel: String
        get() = if (expectedSizeBytes >= GIB) {
            String.format(Locale.US, "%.1f GiB", expectedSizeBytes.toDouble() / GIB)
        } else {
            String.format(Locale.US, "%.1f MiB", expectedSizeBytes.toDouble() / MIB)
        }

    val shaPrefix: String
        get() = sha256.take(12)

    companion object {
        private val ID_PATTERN = Regex("[a-z0-9][a-z0-9_]{0,63}")
        private val FILE_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
        private val SHA_PATTERN = Regex("[0-9a-f]{64}")
        private const val MIB = 1_048_576.0
        private const val GIB = 1_073_741_824.0
    }
}
