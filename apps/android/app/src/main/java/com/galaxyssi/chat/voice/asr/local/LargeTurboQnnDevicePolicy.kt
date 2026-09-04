package com.galaxyssi.chat.voice.asr.local

import java.util.Locale

data class QnnAsrDeviceSnapshot(
    val androidApiLevel: Int,
    val supportedAbis: Set<String>,
    val manufacturer: String,
    val brand: String,
    val hardware: String,
    val socManufacturer: String,
    val socModel: String,
    val nativeLibraries: Set<String>,
    val qnnRuntimeVersion: String?,
    val availableMemoryBytes: Long,
    val availableStorageBytes: Long,
    val activeModelState: QnnContextModelState
)

enum class QnnAsrEligibility {
    READY,
    MODEL_DOWNLOAD_REQUIRED,
    FALLBACK_REQUIRED
}

enum class QnnAsrFallbackTarget {
    SMALL_OR_BASE_QNN,
    WHISPER_CPP,
    SYSTEM_ASR
}

data class QnnAsrDeviceDecision(
    val eligibility: QnnAsrEligibility,
    val reasonCode: String,
    val detail: String,
    val fallbackOrder: List<QnnAsrFallbackTarget> = emptyList(),
    val advisories: Set<String> = emptySet()
)

class LargeTurboQnnDevicePolicy(
    private val manifest: LargeTurboQnnModelManifest = LargeTurboQnnModelCatalog.s26Ultra,
    private val minimumAndroidApi: Int = 35
) {
    fun evaluate(snapshot: QnnAsrDeviceSnapshot): QnnAsrDeviceDecision {
        if (snapshot.androidApiLevel < minimumAndroidApi) {
            return fallback("android_version_unsupported", "This QNN model requires a newer Android runtime")
        }
        if (snapshot.supportedAbis.none { normalize(it) == "arm64v8a" }) {
            return fallback("arm64_required", "The QNN Context Binary requires arm64-v8a")
        }
        if (!matchesTargetChipset(snapshot)) {
            return fallback("chipset_mismatch", "The installed QNN Context Binary does not target this chipset")
        }
        val missingLibraries = REQUIRED_LIBRARIES.filterNot { requirement ->
            snapshot.nativeLibraries.any { normalize(it).contains(requirement) }
        }
        if (missingLibraries.isNotEmpty()) {
            return fallback("qnn_runtime_missing", "The matching QAIRT HTP runtime is incomplete")
        }
        if (!runtimeCompatible(snapshot.qnnRuntimeVersion)) {
            return fallback("qnn_runtime_incompatible", "The QNN runtime does not match QAIRT ${manifest.qairtVersion}")
        }

        val advisories = buildSet {
            if (snapshot.availableMemoryBytes in 1 until RECOMMENDED_AVAILABLE_MEMORY_BYTES) {
                add("memory_headroom_low")
            }
            if (snapshot.availableStorageBytes in 1 until requiredInstallStorageBytes()) {
                add("storage_headroom_low")
            }
        }
        return if (snapshot.activeModelState == QnnContextModelState.INSTALLED) {
            QnnAsrDeviceDecision(
                QnnAsrEligibility.READY,
                "large_turbo_qnn_ready",
                "Whisper Large-v3-Turbo is compatible with the device",
                advisories = advisories
            )
        } else {
            QnnAsrDeviceDecision(
                QnnAsrEligibility.MODEL_DOWNLOAD_REQUIRED,
                "large_turbo_model_required",
                "Download and verify the S26U QNN model before use",
                advisories = advisories
            )
        }
    }

    private fun matchesTargetChipset(snapshot: QnnAsrDeviceSnapshot): Boolean {
        val identity = listOf(
            snapshot.manufacturer,
            snapshot.brand,
            snapshot.hardware,
            snapshot.socManufacturer,
            snapshot.socModel
        ).joinToString(" ") { normalize(it) }
        val normalizedSoc = normalize(snapshot.socModel)
        return manifest.targetAliases.map(::normalize).any { alias ->
            alias.isNotBlank() && (identity.contains(alias) ||
                normalizedSoc.isNotBlank() && alias.contains(normalizedSoc))
        }
    }

    private fun requiredInstallStorageBytes(): Long = manifest.totalInstalledSizeBytes +
        MIN_FREE_AFTER_INSTALL_BYTES

    private fun runtimeCompatible(version: String?): Boolean {
        val actual = version.toMajorMinor() ?: return false
        val required = manifest.qairtVersion.toMajorMinor() ?: return false
        return actual.first == required.first && actual.second >= required.second
    }

    private fun String?.toMajorMinor(): Pair<Int, Int>? {
        val components = this?.split('.') ?: return null
        if (components.size < 2) return null
        val major = components[0].toIntOrNull() ?: return null
        val minor = components[1].toIntOrNull() ?: return null
        return major to minor
    }

    private fun fallback(reason: String, detail: String) = QnnAsrDeviceDecision(
        eligibility = QnnAsrEligibility.FALLBACK_REQUIRED,
        reasonCode = reason,
        detail = detail,
        fallbackOrder = listOf(
            QnnAsrFallbackTarget.SMALL_OR_BASE_QNN,
            QnnAsrFallbackTarget.WHISPER_CPP,
            QnnAsrFallbackTarget.SYSTEM_ASR
        )
    )

    private fun normalize(value: String): String = value.lowercase(Locale.ROOT)
        .replace(Regex("[^a-z0-9]"), "")

    private companion object {
        val REQUIRED_LIBRARIES = setOf("libqnnsystemso", "libqnnhtpso", "libqnnhtpv81stubso")
        const val RECOMMENDED_AVAILABLE_MEMORY_BYTES = 3L * 1024L * 1024L * 1024L
        const val MIN_FREE_AFTER_INSTALL_BYTES = 512L * 1024L * 1024L
    }
}
