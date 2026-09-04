package com.galaxyssi.chat.voice.reliability

import android.os.PowerManager

enum class VoiceResourceMode {
    NORMAL,
    CONSERVE,
    DEGRADED,
    BLOCKED
}

enum class VoiceResourceReason {
    NONE,
    LOW_MEMORY_SIGNAL,
    INSUFFICIENT_MEMORY_HEADROOM,
    MEMORY_PRESSURE,
    THERMAL_MODERATE,
    THERMAL_SEVERE,
    THERMAL_CRITICAL,
    THERMAL_SHUTDOWN,
    CRITICAL_BATTERY,
    BACKGROUND_RESTRICTED,
    NETWORK_UNAVAILABLE,
    CIRCUIT_OPEN,
    ROLLOUT_BLOCKED
}

data class VoiceResourceSnapshot(
    val elapsedRealtimeMs: Long,
    val availableMemoryBytes: Long,
    val totalMemoryBytes: Long,
    val currentPssBytes: Long,
    val otherLocalModelBytes: Long = 0L,
    val lowMemory: Boolean = false,
    val thermalStatus: Int = PowerManager.THERMAL_STATUS_NONE,
    val batteryPercent: Int? = null,
    val charging: Boolean = false,
    val foreground: Boolean = true,
    val networkAvailable: Boolean = true,
    val networkMetered: Boolean = false
)

data class VoiceWorkloadProfile(
    val feature: VoicePipelineFeature,
    val profileId: String = "",
    val estimatedPeakPssBytes: Long = 0L,
    val estimatedIncrementalMemoryBytes: Long? = null,
    val certifiedPeakPssBytes: Long = 0L,
    val minimumSafetyMarginBytes: Long = DEFAULT_MINIMUM_SAFETY_MARGIN_BYTES,
    val localInference: Boolean = false,
    val highMemoryLocalModel: Boolean = false,
    val requiresNetwork: Boolean = false,
    val allowBackground: Boolean = true,
    val supportsReducedConcurrency: Boolean = true
) {
    companion object {
        const val DEFAULT_MINIMUM_SAFETY_MARGIN_BYTES = 256L * 1024L * 1024L
    }
}

data class VoiceMemoryGateDecision(
    val allowed: Boolean,
    val requiredHeadroomBytes: Long,
    val availableHeadroomBytes: Long,
    val safetyMarginBytes: Long,
    val reason: VoiceResourceReason = VoiceResourceReason.NONE
)

class VoiceMemoryGate {
    fun evaluate(snapshot: VoiceResourceSnapshot, workload: VoiceWorkloadProfile): VoiceMemoryGateDecision {
        if (!workload.localInference) {
            return VoiceMemoryGateDecision(
                allowed = true,
                requiredHeadroomBytes = 0L,
                availableHeadroomBytes = snapshot.availableMemoryBytes.coerceAtLeast(0L),
                safetyMarginBytes = 0L
            )
        }
        val safetyMargin = maxOf(
            workload.minimumSafetyMarginBytes,
            (snapshot.totalMemoryBytes.coerceAtLeast(0L) / 10L).coerceAtMost(MAX_DYNAMIC_SAFETY_MARGIN_BYTES)
        )
        val incrementalPeak = workload.estimatedIncrementalMemoryBytes
            ?.coerceAtLeast(0L)
            ?: run {
                val measuredPeak = workload.certifiedPeakPssBytes.takeIf { it > 0L }
                    ?: workload.estimatedPeakPssBytes.coerceAtLeast(snapshot.currentPssBytes)
                (measuredPeak - snapshot.currentPssBytes).coerceAtLeast(0L)
            }
        val required = saturatedAdd(
            saturatedAdd(incrementalPeak, safetyMargin),
            snapshot.otherLocalModelBytes.coerceAtLeast(0L)
        )
        val available = snapshot.availableMemoryBytes.coerceAtLeast(0L)
        val reason = when {
            snapshot.lowMemory -> VoiceResourceReason.LOW_MEMORY_SIGNAL
            required > available -> VoiceResourceReason.INSUFFICIENT_MEMORY_HEADROOM
            else -> VoiceResourceReason.NONE
        }
        return VoiceMemoryGateDecision(
            allowed = reason == VoiceResourceReason.NONE,
            requiredHeadroomBytes = required,
            availableHeadroomBytes = available,
            safetyMarginBytes = safetyMargin,
            reason = reason
        )
    }

    private fun saturatedAdd(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right

    companion object {
        private const val MAX_DYNAMIC_SAFETY_MARGIN_BYTES = 768L * 1024L * 1024L
    }
}

data class VoiceThermalDecision(
    val effectiveStatus: Int,
    val mode: VoiceResourceMode,
    val partialIntervalMultiplier: Int,
    val maximumThreads: Int?,
    val allowSecondPass: Boolean,
    val releaseLargeModels: Boolean,
    val reason: VoiceResourceReason = VoiceResourceReason.NONE,
    val cooldownRemainingMs: Long = 0L
)

class VoiceThermalController(
    private val elapsedRealtime: () -> Long,
    private val moderateCooldownMs: Long = 30_000L,
    private val severeCooldownMs: Long = 90_000L,
    private val criticalCooldownMs: Long = 180_000L
) {
    private var heldStatus = PowerManager.THERMAL_STATUS_NONE
    private var releaseAtMs = 0L

    @Synchronized
    fun evaluate(observedStatus: Int): VoiceThermalDecision {
        val now = elapsedRealtime().coerceAtLeast(0L)
        val observed = observedStatus.coerceIn(
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_SHUTDOWN
        )
        if (observed >= PowerManager.THERMAL_STATUS_MODERATE) {
            if (observed >= heldStatus || now >= releaseAtMs) {
                heldStatus = observed
                releaseAtMs = now + cooldownFor(observed)
            }
        } else if (now >= releaseAtMs) {
            heldStatus = PowerManager.THERMAL_STATUS_NONE
            releaseAtMs = 0L
        }
        val effective = maxOf(observed, heldStatus)
        val remaining = (releaseAtMs - now).coerceAtLeast(0L)
        return when {
            effective >= PowerManager.THERMAL_STATUS_SHUTDOWN -> VoiceThermalDecision(
                effective, VoiceResourceMode.BLOCKED, 4, 1, false, true,
                VoiceResourceReason.THERMAL_SHUTDOWN, remaining
            )
            effective >= PowerManager.THERMAL_STATUS_CRITICAL -> VoiceThermalDecision(
                effective, VoiceResourceMode.BLOCKED, 4, 1, false, true,
                VoiceResourceReason.THERMAL_CRITICAL, remaining
            )
            effective >= PowerManager.THERMAL_STATUS_SEVERE -> VoiceThermalDecision(
                effective, VoiceResourceMode.DEGRADED, 4, 2, false, true,
                VoiceResourceReason.THERMAL_SEVERE, remaining
            )
            effective >= PowerManager.THERMAL_STATUS_MODERATE -> VoiceThermalDecision(
                effective, VoiceResourceMode.CONSERVE, 2, 2, true, false,
                VoiceResourceReason.THERMAL_MODERATE, remaining
            )
            else -> VoiceThermalDecision(
                effective, VoiceResourceMode.NORMAL, 1, null, true, false
            )
        }
    }

    @Synchronized
    fun reset() {
        heldStatus = PowerManager.THERMAL_STATUS_NONE
        releaseAtMs = 0L
    }

    @Synchronized
    fun remainingCooldownMs(): Long =
        (releaseAtMs - elapsedRealtime().coerceAtLeast(0L)).coerceAtLeast(0L)

    private fun cooldownFor(status: Int): Long = when {
        status >= PowerManager.THERMAL_STATUS_CRITICAL -> criticalCooldownMs
        status >= PowerManager.THERMAL_STATUS_SEVERE -> severeCooldownMs
        else -> moderateCooldownMs
    }
}

data class VoiceResourceDecision(
    val allowed: Boolean,
    val mode: VoiceResourceMode,
    val reasons: Set<VoiceResourceReason>,
    val memory: VoiceMemoryGateDecision,
    val thermal: VoiceThermalDecision,
    val maximumThreads: Int?,
    val partialIntervalMultiplier: Int,
    val allowSecondPass: Boolean,
    val releaseLargeModels: Boolean
)

class VoiceResourceGovernor(
    private val memoryGate: VoiceMemoryGate = VoiceMemoryGate(),
    private val thermalController: VoiceThermalController
) {
    fun evaluate(snapshot: VoiceResourceSnapshot, workload: VoiceWorkloadProfile): VoiceResourceDecision {
        val memory = memoryGate.evaluate(snapshot, workload)
        val thermal = thermalController.evaluate(snapshot.thermalStatus)
        val reasons = linkedSetOf<VoiceResourceReason>()
        if (!memory.allowed) reasons += memory.reason
        if (thermal.reason != VoiceResourceReason.NONE) reasons += thermal.reason
        if (workload.requiresNetwork && !snapshot.networkAvailable) {
            reasons += VoiceResourceReason.NETWORK_UNAVAILABLE
        }
        if (!workload.allowBackground && !snapshot.foreground) {
            reasons += VoiceResourceReason.BACKGROUND_RESTRICTED
        }
        val highMemoryThermalBlock = workload.localInference && workload.highMemoryLocalModel &&
            thermal.releaseLargeModels
        val hardBlocked = reasons.any { it in HARD_BLOCK_REASONS } || highMemoryThermalBlock
        val memoryPressure = memory.allowed && workload.localInference &&
            memory.availableHeadroomBytes < memory.requiredHeadroomBytes + memory.safetyMarginBytes
        if (memoryPressure) reasons += VoiceResourceReason.MEMORY_PRESSURE
        val mode = when {
            hardBlocked -> VoiceResourceMode.BLOCKED
            thermal.mode == VoiceResourceMode.DEGRADED -> VoiceResourceMode.DEGRADED
            thermal.mode == VoiceResourceMode.CONSERVE || memoryPressure -> VoiceResourceMode.CONSERVE
            else -> VoiceResourceMode.NORMAL
        }
        return VoiceResourceDecision(
            allowed = !hardBlocked,
            mode = mode,
            reasons = reasons,
            memory = memory,
            thermal = thermal,
            maximumThreads = when {
                !workload.supportsReducedConcurrency -> null
                mode == VoiceResourceMode.CONSERVE -> thermal.maximumThreads ?: 2
                mode == VoiceResourceMode.DEGRADED -> thermal.maximumThreads ?: 1
                else -> thermal.maximumThreads
            },
            partialIntervalMultiplier = if (memoryPressure) {
                maxOf(2, thermal.partialIntervalMultiplier)
            } else thermal.partialIntervalMultiplier,
            allowSecondPass = thermal.allowSecondPass && !memoryPressure && !hardBlocked,
            releaseLargeModels = thermal.releaseLargeModels || !memory.allowed
        )
    }

    companion object {
        private val HARD_BLOCK_REASONS = setOf(
            VoiceResourceReason.LOW_MEMORY_SIGNAL,
            VoiceResourceReason.INSUFFICIENT_MEMORY_HEADROOM,
            VoiceResourceReason.THERMAL_CRITICAL,
            VoiceResourceReason.THERMAL_SHUTDOWN,
            VoiceResourceReason.BACKGROUND_RESTRICTED,
            VoiceResourceReason.NETWORK_UNAVAILABLE
        )
    }
}
