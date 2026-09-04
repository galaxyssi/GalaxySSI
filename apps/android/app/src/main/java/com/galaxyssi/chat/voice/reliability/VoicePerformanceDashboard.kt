package com.galaxyssi.chat.voice.reliability

import com.galaxyssi.chat.voice.metrics.VoiceDiagnosticSummary

enum class VoicePerformanceHealth {
    HEALTHY,
    WATCH,
    DEGRADED,
    BLOCKED,
    NO_DATA
}

data class VoicePerformanceMetric(
    val id: String,
    val samples: Int,
    val p50Ms: Long,
    val p95Ms: Long,
    val targetP95Ms: Long?,
    val health: VoicePerformanceHealth
)

data class VoicePerformanceDashboardSnapshot(
    val generatedAtElapsedMs: Long,
    val health: VoicePerformanceHealth,
    val sessionCount: Int,
    val successRate: Double,
    val failureRate: Double,
    val fallbackRate: Double,
    val nativeCrashCount: Int,
    val oomCount: Int,
    val thermalDegradeCount: Int,
    val resourceMode: VoiceResourceMode,
    val resourceReasons: Set<VoiceResourceReason>,
    val openCircuits: List<VoiceCircuitRecord>,
    val rollouts: Map<VoicePipelineFeature, VoiceRolloutDecision>,
    val metrics: List<VoicePerformanceMetric>
)

object VoicePerformanceDashboard {
    private val p95TargetsMs = mapOf(
        "asr_total_ms" to 1_200L,
        "model_first_delta_ms" to 2_500L,
        "tts_first_audio_ms" to 1_500L,
        "tts_playback_ms" to 2_000L,
        "agent_accept_ms" to 1_000L,
        "agent_first_progress_ms" to 3_000L,
        "agent_first_output_ms" to 8_000L
    )

    fun build(
        generatedAtElapsedMs: Long,
        diagnostics: VoiceDiagnosticSummary,
        resource: VoiceResourceDecision,
        circuits: List<VoiceCircuitRecord>,
        rollouts: Collection<VoiceRolloutDecision>
    ): VoicePerformanceDashboardSnapshot {
        val metricRows = diagnostics.metrics.map { (id, value) ->
            val target = p95TargetsMs[id]
            VoicePerformanceMetric(
                id = id,
                samples = value.count,
                p50Ms = value.p50Ms,
                p95Ms = value.p95Ms,
                targetP95Ms = target,
                health = metricHealth(value.count, value.p95Ms, target)
            )
        }.sortedBy(VoicePerformanceMetric::id)
        val open = circuits.filter { it.state != VoiceCircuitState.CLOSED }
        val health = when {
            resource.mode == VoiceResourceMode.BLOCKED || open.isNotEmpty() -> VoicePerformanceHealth.BLOCKED
            diagnostics.traceCount == 0 -> VoicePerformanceHealth.NO_DATA
            diagnostics.nativeCrashCount > 0 || diagnostics.oomCount > 0 ||
                diagnostics.failureRate > 0.10 ||
                metricRows.any { it.health == VoicePerformanceHealth.DEGRADED } ->
                VoicePerformanceHealth.DEGRADED
            resource.mode != VoiceResourceMode.NORMAL || diagnostics.failureRate > 0.03 ||
                metricRows.any { it.health == VoicePerformanceHealth.WATCH } -> VoicePerformanceHealth.WATCH
            else -> VoicePerformanceHealth.HEALTHY
        }
        return VoicePerformanceDashboardSnapshot(
            generatedAtElapsedMs = generatedAtElapsedMs.coerceAtLeast(0L),
            health = health,
            sessionCount = diagnostics.traceCount,
            successRate = diagnostics.successRate,
            failureRate = diagnostics.failureRate,
            fallbackRate = diagnostics.fallbackRate,
            nativeCrashCount = diagnostics.nativeCrashCount,
            oomCount = diagnostics.oomCount,
            thermalDegradeCount = diagnostics.thermalDegradeCount,
            resourceMode = resource.mode,
            resourceReasons = resource.reasons,
            openCircuits = open,
            rollouts = rollouts.associateBy(VoiceRolloutDecision::feature),
            metrics = metricRows
        )
    }

    private fun metricHealth(samples: Int, p95Ms: Long, targetP95Ms: Long?): VoicePerformanceHealth = when {
        samples <= 0 -> VoicePerformanceHealth.NO_DATA
        targetP95Ms == null -> VoicePerformanceHealth.HEALTHY
        p95Ms <= targetP95Ms -> VoicePerformanceHealth.HEALTHY
        p95Ms <= targetP95Ms * 3L / 2L -> VoicePerformanceHealth.WATCH
        else -> VoicePerformanceHealth.DEGRADED
    }
}
