package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelProfile

enum class WhisperUserVoiceMode {
    AUTOMATIC,
    FAST,
    POWER_SAVER,
    ACCURATE,
    PRIVACY,
    MANUAL
}

enum class WhisperProviderChoice {
    LOCAL,
    REMOTE,
    UNAVAILABLE
}

enum class WhisperNetworkState {
    OFFLINE,
    METERED,
    UNMETERED
}

data class WhisperRuntimeEnvironment(
    val network: WhisperNetworkState,
    val availableMemoryBytes: Long,
    val currentPssBytes: Long,
    val thermalStatus: Int,
    val batteryPercent: Int?,
    val charging: Boolean,
    val foreground: Boolean,
    val recentRealTimeFactor: Double?,
    val decodeQueueDepth: Int,
    val utteranceDurationMs: Long,
    val highRiskTask: Boolean,
    val remoteAllowed: Boolean,
    val accuracySensitiveTask: Boolean = false
)

data class WhisperRuntimeCandidate(
    val profile: WhisperModelProfile,
    val installed: Boolean,
    val certification: WhisperCertification?,
    val loaded: Boolean = false
)

data class WhisperRuntimePolicyInput(
    val userMode: WhisperUserVoiceMode,
    val selectedProfileId: String?,
    val candidates: List<WhisperRuntimeCandidate>,
    val environment: WhisperRuntimeEnvironment
)

data class WhisperRuntimeDecision(
    val provider: WhisperProviderChoice,
    val fastProfileId: String?,
    val fastMode: WhisperExecutionMode?,
    val accurateProfileId: String?,
    val accurateMode: WhisperExecutionMode?,
    val partialIntervalMs: Long?,
    val threadCount: Int?,
    val runSecondPass: Boolean,
    val reasons: List<String>
)

object WhisperRuntimePolicyEngine {
    fun decide(input: WhisperRuntimePolicyInput): WhisperRuntimeDecision {
        val environment = input.environment
        val reasons = mutableListOf<String>()
        val usable = input.candidates.filter { candidate ->
            candidate.installed && candidate.certification != null &&
                candidate.certification.level in LOCAL_CERTIFICATION_LEVELS &&
                candidate.certification.key.modelProfileId == candidate.profile.id &&
                memoryAllowed(candidate, environment, reasons) &&
                thermalAllowed(candidate, environment, reasons)
        }
        val realtime = usable
            .filter { it.certification?.realtimeCertified == true }
            .sortedWith(
                compareBy<WhisperRuntimeCandidate> { it.certification?.warmRtfP95 ?: Double.MAX_VALUE }
                    .thenByDescending { qualityRank(it.profile.family) }
            )
        val accurate = usable
            .filter { it.certification?.level in setOf(
                WhisperCertificationLevel.REALTIME,
                WhisperCertificationLevel.FINAL,
                WhisperCertificationLevel.SECOND_PASS
            ) }
            .sortedWith(
                compareByDescending<WhisperRuntimeCandidate> { qualityRank(it.profile.family) }
                    .thenBy { it.certification?.warmRtfP95 ?: Double.MAX_VALUE }
            )
        val selected = input.selectedProfileId?.let { id -> usable.firstOrNull { it.profile.id == id } }
        val conservativeLocalFallbacks = input.candidates
            .filter { candidate ->
                candidate.installed &&
                    (candidate.certification == null ||
                        candidate.certification.level == WhisperCertificationLevel.REMOTE_RECOMMENDED) &&
                    memoryAllowed(candidate, environment, reasons) &&
                    thermalAllowed(candidate, environment, reasons)
            }
            .sortedWith(
                compareByDescending<WhisperRuntimeCandidate> {
                    it.profile.id == input.selectedProfileId
                }.thenBy { qualityRank(it.profile.family) }
            )

        if (environment.thermalStatus >= THERMAL_CRITICAL) {
            reasons += "Critical thermal pressure blocks local Whisper"
            return remoteOrUnavailable(input, reasons)
        }
        return when (input.userMode) {
            WhisperUserVoiceMode.AUTOMATIC, WhisperUserVoiceMode.FAST -> {
                val fast = realtime.firstOrNull()
                if (fast == null) {
                    reasons += "Automatic mode requires a current realtime certification"
                    val remote = remoteOrUnavailable(input, reasons)
                    if (remote.provider != WhisperProviderChoice.UNAVAILABLE) {
                        remote
                    } else {
                        conservativeLocalFallbacks.firstOrNull()?.let { fallback ->
                            reasons += "${fallback.profile.displayName} is used in conservative final-only mode"
                            uncertifiedLocalDecision(fallback, reasons)
                        } ?: remote
                    }
                } else {
                    val certification = requireNotNull(fast.certification)
                    val secondPass = (
                        input.userMode == WhisperUserVoiceMode.AUTOMATIC ||
                            environment.highRiskTask ||
                            environment.accuracySensitiveTask
                        ) &&
                        shouldRunSecondPass(environment) && accurate.firstOrNull { it.profile.id != fast.profile.id } != null
                    val accurateCandidate = if (secondPass) {
                        accurate.firstOrNull { it.profile.id != fast.profile.id }
                    } else null
                    reasons += "${fast.profile.displayName} is realtime-certified at RTF p95=${formatRtf(certification.warmRtfP95)}"
                    localDecision(fast, accurateCandidate, environment, reasons)
                }
            }

            WhisperUserVoiceMode.PRIVACY -> {
                val fast = realtime.firstOrNull()
                if (fast == null) {
                    conservativeLocalFallbacks.firstOrNull()?.let { fallback ->
                        reasons += "Privacy mode uses ${fallback.profile.displayName} in conservative final-only mode"
                        uncertifiedLocalDecision(fallback, reasons)
                    } ?: run {
                        reasons += "Privacy mode has no realtime-certified local model"
                        unavailable(reasons)
                    }
                } else {
                    reasons += "Privacy mode keeps audio on this device"
                    val accurateCandidate = if (environment.highRiskTask && shouldRunSecondPass(environment)) {
                        accurate.firstOrNull { it.profile.id != fast.profile.id }
                    } else null
                    localDecision(fast, accurateCandidate, environment, reasons)
                }
            }

            WhisperUserVoiceMode.POWER_SAVER -> {
                val efficient = selected ?: usable.minByOrNull { it.profile.expectedSizeBytes }
                if (efficient != null) {
                    reasons += "Power saver mode runs local Whisper only at sentence end"
                    localDecision(efficient, null, environment, reasons, forceFinal = true)
                } else {
                    conservativeLocalFallbacks.minByOrNull { it.profile.expectedSizeBytes }
                        ?.let { fallback ->
                            reasons += "Power saver mode uses the smallest available local model"
                            uncertifiedLocalDecision(fallback, reasons)
                        }
                        ?: remoteOrUnavailable(input, reasons)
                }
            }

            WhisperUserVoiceMode.ACCURATE -> {
                val accurateCandidate = accurate.firstOrNull()
                if (accurateCandidate == null) {
                    reasons += "No certified accurate local model is available"
                    remoteOrUnavailable(input, reasons)
                } else {
                    val fast = realtime.firstOrNull()
                    if (fast != null && fast.profile.id != accurateCandidate.profile.id) {
                        reasons += "Realtime pass is followed by a certified accuracy pass"
                        localDecision(fast, accurateCandidate, environment, reasons)
                    } else {
                        reasons += "Accurate mode uses ${accurateCandidate.profile.displayName} in final mode"
                        localDecision(accurateCandidate, null, environment, reasons, forceFinal = true)
                    }
                }
            }

            WhisperUserVoiceMode.MANUAL -> {
                if (selected == null) {
                    conservativeLocalFallbacks
                        .firstOrNull { it.profile.id == input.selectedProfileId }
                        ?.let { fallback ->
                            reasons += "The selected model is used in conservative final-only mode"
                            uncertifiedLocalDecision(fallback, reasons)
                        }
                        ?: run {
                            reasons += "The selected model has no current certification"
                            remoteOrUnavailable(input, reasons)
                        }
                } else {
                    reasons += "Manual mode uses the selected certified model"
                    val accurateCandidate = if (environment.highRiskTask && shouldRunSecondPass(environment)) {
                        accurate.firstOrNull { it.profile.id != selected.profile.id }
                    } else null
                    localDecision(
                        selected,
                        accurateCandidate,
                        environment,
                        reasons,
                        forceFinal = selected.certification?.realtimeCertified != true
                    )
                }
            }
        }
    }

    private fun localDecision(
        fast: WhisperRuntimeCandidate,
        accurate: WhisperRuntimeCandidate?,
        environment: WhisperRuntimeEnvironment,
        reasons: MutableList<String>,
        forceFinal: Boolean = false
    ): WhisperRuntimeDecision {
        val certification = requireNotNull(fast.certification)
        val thermalConstrained = environment.thermalStatus >= THERMAL_SEVERE
        val backlogConstrained = environment.decodeQueueDepth >= 2 ||
            (environment.recentRealTimeFactor ?: 0.0) > 1.0
        val mode = if (forceFinal || thermalConstrained) {
            WhisperExecutionMode.FINAL_ONLY
        } else {
            certification.recommendedMode
        }
        val partialInterval = if (mode == WhisperExecutionMode.REALTIME_PARTIAL) {
            certification.recommendedPartialIntervalMs
                .times(if (backlogConstrained) 2L else 1L)
                .times(if (environment.thermalStatus >= THERMAL_MODERATE) 2L else 1L)
                .coerceIn(MIN_PARTIAL_INTERVAL_MS, MAX_PARTIAL_INTERVAL_MS)
        } else null
        val threads = certification.recommendedThreadCount
            .let { if (thermalConstrained || environment.thermalStatus >= THERMAL_MODERATE) minOf(it, 2) else it }
            .coerceAtLeast(1)
        if (thermalConstrained) reasons += "Severe thermal pressure disables realtime partial decoding"
        if (backlogConstrained && partialInterval != null) reasons += "Decode backlog increased the partial interval"
        return WhisperRuntimeDecision(
            provider = WhisperProviderChoice.LOCAL,
            fastProfileId = fast.profile.id,
            fastMode = mode,
            accurateProfileId = accurate?.profile?.id,
            accurateMode = accurate?.certification?.recommendedMode,
            partialIntervalMs = partialInterval,
            threadCount = threads,
            runSecondPass = accurate != null && environment.thermalStatus < THERMAL_SEVERE,
            reasons = reasons.distinct()
        )
    }

    private fun uncertifiedLocalDecision(
        candidate: WhisperRuntimeCandidate,
        reasons: List<String>
    ): WhisperRuntimeDecision = WhisperRuntimeDecision(
        provider = WhisperProviderChoice.LOCAL,
        fastProfileId = candidate.profile.id,
        fastMode = WhisperExecutionMode.FINAL_ONLY,
        accurateProfileId = null,
        accurateMode = null,
        partialIntervalMs = null,
        threadCount = 2,
        runSecondPass = false,
        reasons = reasons.distinct()
    )

    private fun memoryAllowed(
        candidate: WhisperRuntimeCandidate,
        environment: WhisperRuntimeEnvironment,
        reasons: MutableList<String>
    ): Boolean {
        val decision = WhisperMemoryAdmissionPolicy.evaluate(
            profile = candidate.profile,
            availableMemoryBytes = environment.availableMemoryBytes,
            currentPssBytes = environment.currentPssBytes,
            certifiedPeakPssBytes = candidate.certification?.peakPssBytes ?: 0L,
            alreadyLoaded = candidate.loaded,
            safetyMarginBytes = MEMORY_SAFETY_MARGIN_BYTES
        )
        if (!decision.allowed) {
            reasons += "${candidate.profile.displayName} needs more certified memory headroom"
        }
        return decision.allowed
    }

    private fun thermalAllowed(
        candidate: WhisperRuntimeCandidate,
        environment: WhisperRuntimeEnvironment,
        reasons: MutableList<String>
    ): Boolean {
        if (environment.thermalStatus < THERMAL_SEVERE) return true
        val large = candidate.profile.family in setOf(
            WhisperModelFamily.MEDIUM,
            WhisperModelFamily.LARGE_V3,
            WhisperModelFamily.LARGE_V3_TURBO
        )
        if (large) reasons += "${candidate.profile.displayName} is blocked by severe thermal pressure"
        return !large
    }

    private fun shouldRunSecondPass(environment: WhisperRuntimeEnvironment): Boolean =
        environment.foreground &&
            environment.thermalStatus < THERMAL_SEVERE &&
            environment.decodeQueueDepth == 0 &&
            (environment.highRiskTask ||
                environment.accuracySensitiveTask ||
                environment.utteranceDurationMs >= MIN_SECOND_PASS_AUDIO_MS)

    private fun remoteOrUnavailable(
        input: WhisperRuntimePolicyInput,
        reasons: MutableList<String>
    ): WhisperRuntimeDecision {
        val environment = input.environment
        return if (environment.remoteAllowed && environment.network != WhisperNetworkState.OFFLINE &&
            input.userMode != WhisperUserVoiceMode.PRIVACY
        ) {
            reasons += "A remote ASR provider is recommended"
            WhisperRuntimeDecision(
                provider = WhisperProviderChoice.REMOTE,
                fastProfileId = null,
                fastMode = WhisperExecutionMode.REMOTE_NODE,
                accurateProfileId = null,
                accurateMode = null,
                partialIntervalMs = null,
                threadCount = null,
                runSecondPass = false,
                reasons = reasons.distinct()
            )
        } else unavailable(reasons)
    }

    private fun unavailable(reasons: List<String>): WhisperRuntimeDecision = WhisperRuntimeDecision(
        provider = WhisperProviderChoice.UNAVAILABLE,
        fastProfileId = null,
        fastMode = null,
        accurateProfileId = null,
        accurateMode = null,
        partialIntervalMs = null,
        threadCount = null,
        runSecondPass = false,
        reasons = reasons.distinct()
    )

    private fun qualityRank(family: WhisperModelFamily): Int = when (family) {
        WhisperModelFamily.TINY -> 1
        WhisperModelFamily.BASE -> 2
        WhisperModelFamily.SMALL -> 3
        WhisperModelFamily.MEDIUM -> 4
        WhisperModelFamily.LARGE_V3_TURBO -> 5
        WhisperModelFamily.LARGE_V3 -> 6
    }

    private fun formatRtf(value: Double): String = "%.2f".format(java.util.Locale.US, value)

    private const val MEMORY_SAFETY_MARGIN_BYTES = 256L * 1024L * 1024L
    private const val MIN_PARTIAL_INTERVAL_MS = 400L
    private const val MAX_PARTIAL_INTERVAL_MS = 8_000L
    private const val MIN_SECOND_PASS_AUDIO_MS = 3_000L
    private const val THERMAL_MODERATE = 2
    private const val THERMAL_SEVERE = 3
    private const val THERMAL_CRITICAL = 4
    private val LOCAL_CERTIFICATION_LEVELS = setOf(
        WhisperCertificationLevel.REALTIME,
        WhisperCertificationLevel.FINAL,
        WhisperCertificationLevel.SECOND_PASS
    )
}
