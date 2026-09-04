package com.galaxyssi.chat.voice.reliability

import java.security.MessageDigest

enum class VoiceRolloutStage {
    DEVELOPER,
    INTERNAL,
    OPT_IN_BETA,
    STABLE_COHORT,
    CERTIFIED_EXPANSION,
    DEFAULT_WITH_FALLBACK
}

enum class VoiceRollbackLevel {
    NONE,
    DISABLE_SINGLE_OPTIMIZATION,
    FINAL_ONLY,
    LEGACY_PIPELINE,
    TEXT_ONLY
}

data class VoiceRolloutConfig(
    val feature: VoicePipelineFeature,
    val stage: VoiceRolloutStage,
    val cohortPercent: Int = 0,
    val requestedEnabled: Boolean = false,
    val explicitlyDisabled: Boolean = false,
    val debuggable: Boolean = false,
    val internalTester: Boolean = false,
    val betaOptIn: Boolean = false
)

data class VoiceRolloutEvidence(
    val sampleCount: Int = 0,
    val stableReleaseCount: Int = 0,
    val newP95Ms: Long? = null,
    val legacyP95Ms: Long? = null,
    val crashRate: Double = 0.0,
    val legacyCrashRate: Double = 0.0,
    val anrRate: Double = 0.0,
    val legacyAnrRate: Double = 0.0,
    val fallbackSuccessRate: Double = 1.0,
    val privacyReviewed: Boolean = false,
    val securityReviewed: Boolean = false,
    val diagnosticsAvailable: Boolean = false,
    val supportDocumentationAvailable: Boolean = false,
    val deviceCertified: Boolean = false,
    val circuitState: VoiceCircuitState = VoiceCircuitState.CLOSED
)

data class VoiceRolloutDecision(
    val feature: VoicePipelineFeature,
    val enabled: Boolean,
    val stage: VoiceRolloutStage,
    val cohortBucket: Int,
    val rollbackLevel: VoiceRollbackLevel,
    val reasonCodes: List<String>
)

object VoiceRolloutPolicy {
    fun decide(
        config: VoiceRolloutConfig,
        evidence: VoiceRolloutEvidence,
        stableDeviceId: String
    ): VoiceRolloutDecision {
        val bucket = VoiceCohortAssigner.bucket(stableDeviceId, config.feature)
        if (config.explicitlyDisabled) {
            return disabled(config, bucket, VoiceRollbackLevel.LEGACY_PIPELINE, "explicitly_disabled")
        }
        if (evidence.circuitState != VoiceCircuitState.CLOSED) {
            return disabled(config, bucket, rollbackFor(config.feature), "circuit_open")
        }
        val hardSafety = mutableListOf<String>()
        if (!evidence.privacyReviewed) hardSafety += "privacy_review_required"
        if (!evidence.securityReviewed) hardSafety += "security_review_required"
        if (!evidence.diagnosticsAvailable) hardSafety += "diagnostics_required"
        if (requiresDeviceCertification(config.feature) && !evidence.deviceCertified) {
            hardSafety += "device_certification_required"
        }
        if (hardSafety.isNotEmpty()) {
            return disabled(config, bucket, rollbackFor(config.feature), *hardSafety.toTypedArray())
        }

        val audienceEligible = when (config.stage) {
            VoiceRolloutStage.DEVELOPER -> config.debuggable
            VoiceRolloutStage.INTERNAL -> config.internalTester || config.debuggable
            VoiceRolloutStage.OPT_IN_BETA -> config.betaOptIn || config.requestedEnabled
            VoiceRolloutStage.STABLE_COHORT,
            VoiceRolloutStage.CERTIFIED_EXPANSION -> bucket < config.cohortPercent.coerceIn(0, 100)
            VoiceRolloutStage.DEFAULT_WITH_FALLBACK -> true
        }
        if (!audienceEligible) {
            return disabled(config, bucket, VoiceRollbackLevel.LEGACY_PIPELINE, "outside_rollout_audience")
        }

        if (config.stage.ordinal >= VoiceRolloutStage.STABLE_COHORT.ordinal) {
            val qualityFailures = qualityGateFailures(config.stage, evidence)
            if (qualityFailures.isNotEmpty()) {
                return disabled(config, bucket, rollbackFor(config.feature), *qualityFailures.toTypedArray())
            }
        }
        return VoiceRolloutDecision(
            feature = config.feature,
            enabled = true,
            stage = config.stage,
            cohortBucket = bucket,
            rollbackLevel = VoiceRollbackLevel.NONE,
            reasonCodes = listOf("rollout_eligible")
        )
    }

    private fun qualityGateFailures(
        stage: VoiceRolloutStage,
        evidence: VoiceRolloutEvidence
    ): List<String> = buildList {
        val minimumSamples = when (stage) {
            VoiceRolloutStage.STABLE_COHORT -> 30
            VoiceRolloutStage.CERTIFIED_EXPANSION -> 100
            VoiceRolloutStage.DEFAULT_WITH_FALLBACK -> 300
            else -> 0
        }
        if (evidence.sampleCount < minimumSamples) add("insufficient_samples")
        if (evidence.stableReleaseCount < 2) add("insufficient_stable_releases")
        if (evidence.crashRate > evidence.legacyCrashRate + MAX_RATE_REGRESSION) add("crash_rate_regression")
        if (evidence.anrRate > evidence.legacyAnrRate + MAX_RATE_REGRESSION) add("anr_rate_regression")
        if (evidence.fallbackSuccessRate < MINIMUM_FALLBACK_SUCCESS_RATE) add("fallback_unreliable")
        val newP95 = evidence.newP95Ms
        val legacyP95 = evidence.legacyP95Ms
        if (newP95 == null || legacyP95 == null || legacyP95 <= 0L) {
            add("p95_evidence_missing")
        } else if (newP95 > (legacyP95 * MAXIMUM_P95_RATIO).toLong()) {
            add("p95_not_improved")
        }
        if (!evidence.supportDocumentationAvailable) add("support_documentation_required")
    }

    private fun disabled(
        config: VoiceRolloutConfig,
        bucket: Int,
        rollback: VoiceRollbackLevel,
        vararg reasons: String
    ) = VoiceRolloutDecision(
        feature = config.feature,
        enabled = false,
        stage = config.stage,
        cohortBucket = bucket,
        rollbackLevel = rollback,
        reasonCodes = reasons.toList()
    )

    private fun requiresDeviceCertification(feature: VoicePipelineFeature): Boolean = feature in setOf(
        VoicePipelineFeature.LOCAL_WHISPER_REALTIME,
        VoicePipelineFeature.PCM_CAPTURE
    )

    private fun rollbackFor(feature: VoicePipelineFeature): VoiceRollbackLevel = when (feature) {
        VoicePipelineFeature.LOCAL_WHISPER_REALTIME -> VoiceRollbackLevel.FINAL_ONLY
        VoicePipelineFeature.PCM_CAPTURE,
        VoicePipelineFeature.ONLINE_REALTIME_ASR,
        VoicePipelineFeature.CLOUD_MODEL_STREAM,
        VoicePipelineFeature.PROGRESSIVE_TTS,
        VoicePipelineFeature.AGENT_OUTPUT_DELTA -> VoiceRollbackLevel.DISABLE_SINGLE_OPTIMIZATION
    }

    private const val MAX_RATE_REGRESSION = 0.001
    private const val MINIMUM_FALLBACK_SUCCESS_RATE = 0.98
    private const val MAXIMUM_P95_RATIO = 0.95
}

object VoiceCohortAssigner {
    fun bucket(stableDeviceId: String, feature: VoicePipelineFeature): Int {
        val identity = stableDeviceId.trim().ifBlank { "anonymous-device" }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$identity:${feature.name}".toByteArray(Charsets.UTF_8))
        val unsigned = ((digest[0].toInt() and 0xff) shl 8) or (digest[1].toInt() and 0xff)
        return unsigned % 100
    }
}
