package com.galaxyssi.chat.voice.reliability

enum class VoicePipelineFeature {
    PCM_CAPTURE,
    LOCAL_WHISPER_REALTIME,
    ONLINE_REALTIME_ASR,
    CLOUD_MODEL_STREAM,
    PROGRESSIVE_TTS,
    AGENT_OUTPUT_DELTA
}

enum class VoiceFailureKind {
    TRANSIENT_NETWORK,
    TIMEOUT,
    PROVIDER_PROTOCOL,
    MODEL_VERIFICATION,
    NATIVE_CRASH,
    OUT_OF_MEMORY,
    THERMAL_PRESSURE,
    TTS_UNDERRUN,
    AGENT_PROTOCOL,
    CANCELLED,
    USER_ABORT,
    UNKNOWN
}

enum class VoiceCircuitState {
    CLOSED,
    OPEN,
    HALF_OPEN
}

data class VoiceCircuitKey(
    val feature: VoicePipelineFeature,
    val profileId: String = ""
) {
    val storageKey: String
        get() = if (profileId.isBlank()) feature.name else "${feature.name}:${profileId.trim()}"
}

data class VoiceCircuitRecord(
    val key: VoiceCircuitKey,
    val state: VoiceCircuitState = VoiceCircuitState.CLOSED,
    val consecutiveFailures: Int = 0,
    val failureWindowStartedAtMs: Long = 0L,
    val openedAtMs: Long = 0L,
    val openUntilMs: Long = 0L,
    val halfOpenProbeInFlight: Boolean = false,
    val lastFailureKind: VoiceFailureKind? = null,
    val lastFailureCode: String = "",
    val successCount: Long = 0L,
    val failureCount: Long = 0L,
    val generation: String = ""
)

data class VoiceCircuitAdmission(
    val allowed: Boolean,
    val state: VoiceCircuitState,
    val retryAfterMs: Long = 0L,
    val reasonCode: String = ""
)

data class VoiceCircuitBreakerConfig(
    val rollingWindowMs: Long = 2 * 60_000L,
    val transientFailureThreshold: Int = 4,
    val timeoutFailureThreshold: Int = 3,
    val protocolFailureThreshold: Int = 3,
    val thermalFailureThreshold: Int = 2,
    val nativeCrashThreshold: Int = 2,
    val defaultOpenMs: Long = 60_000L,
    val timeoutOpenMs: Long = 90_000L,
    val thermalOpenMs: Long = 3 * 60_000L,
    val nativeOpenMs: Long = 15 * 60_000L,
    val outOfMemoryOpenMs: Long = 5 * 60_000L
)

class VoiceCircuitBreaker(
    private val elapsedRealtime: () -> Long,
    private val config: VoiceCircuitBreakerConfig = VoiceCircuitBreakerConfig(),
    initialRecords: Collection<VoiceCircuitRecord> = emptyList()
) {
    private val records = initialRecords.associateByTo(linkedMapOf(), VoiceCircuitRecord::key)

    @Synchronized
    fun admit(key: VoiceCircuitKey, generation: String = ""): VoiceCircuitAdmission {
        val now = elapsedRealtime().coerceAtLeast(0L)
        var record = currentForGeneration(key, generation)
        if (record.state == VoiceCircuitState.OPEN && now >= record.openUntilMs) {
            record = record.copy(
                state = VoiceCircuitState.HALF_OPEN,
                halfOpenProbeInFlight = false
            )
            records[key] = record
        }
        return when (record.state) {
            VoiceCircuitState.CLOSED -> VoiceCircuitAdmission(true, record.state)
            VoiceCircuitState.OPEN -> VoiceCircuitAdmission(
                allowed = false,
                state = record.state,
                retryAfterMs = (record.openUntilMs - now).coerceAtLeast(0L),
                reasonCode = record.lastFailureCode.ifBlank { record.lastFailureKind?.name.orEmpty() }
            )
            VoiceCircuitState.HALF_OPEN -> if (record.halfOpenProbeInFlight) {
                VoiceCircuitAdmission(
                    allowed = false,
                    state = record.state,
                    retryAfterMs = config.defaultOpenMs,
                    reasonCode = "half_open_probe_in_flight"
                )
            } else {
                records[key] = record.copy(halfOpenProbeInFlight = true)
                VoiceCircuitAdmission(true, VoiceCircuitState.HALF_OPEN)
            }
        }
    }

    @Synchronized
    fun success(key: VoiceCircuitKey, generation: String = ""): VoiceCircuitRecord {
        val current = currentForGeneration(key, generation)
        return current.copy(
            state = VoiceCircuitState.CLOSED,
            consecutiveFailures = 0,
            failureWindowStartedAtMs = 0L,
            openedAtMs = 0L,
            openUntilMs = 0L,
            halfOpenProbeInFlight = false,
            lastFailureKind = null,
            lastFailureCode = "",
            successCount = current.successCount + 1L,
            generation = generation
        ).also { records[key] = it }
    }

    @Synchronized
    fun failure(
        key: VoiceCircuitKey,
        kind: VoiceFailureKind,
        reasonCode: String = "",
        generation: String = ""
    ): VoiceCircuitRecord {
        var current = currentForGeneration(key, generation)
        if (kind == VoiceFailureKind.CANCELLED || kind == VoiceFailureKind.USER_ABORT) {
            current = current.copy(halfOpenProbeInFlight = false)
            records[key] = current
            return current
        }
        val now = elapsedRealtime().coerceAtLeast(0L)
        val inWindow = current.failureWindowStartedAtMs > 0L &&
            now - current.failureWindowStartedAtMs <= config.rollingWindowMs
        val failures = if (inWindow) current.consecutiveFailures + 1 else 1
        val windowStart = if (inWindow) current.failureWindowStartedAtMs else now
        val threshold = thresholdFor(kind)
        val shouldOpen = current.state == VoiceCircuitState.HALF_OPEN || failures >= threshold
        val sanitizedCode = sanitizeReason(reasonCode).ifBlank { kind.name.lowercase() }
        val updated = if (shouldOpen) {
            current.copy(
                state = VoiceCircuitState.OPEN,
                consecutiveFailures = failures,
                failureWindowStartedAtMs = windowStart,
                openedAtMs = now,
                openUntilMs = now + openDurationFor(kind),
                halfOpenProbeInFlight = false,
                lastFailureKind = kind,
                lastFailureCode = sanitizedCode,
                failureCount = current.failureCount + 1L,
                generation = generation
            )
        } else {
            current.copy(
                state = VoiceCircuitState.CLOSED,
                consecutiveFailures = failures,
                failureWindowStartedAtMs = windowStart,
                halfOpenProbeInFlight = false,
                lastFailureKind = kind,
                lastFailureCode = sanitizedCode,
                failureCount = current.failureCount + 1L,
                generation = generation
            )
        }
        records[key] = updated
        return updated
    }

    @Synchronized
    fun snapshot(key: VoiceCircuitKey, generation: String = ""): VoiceCircuitRecord =
        currentForGeneration(key, generation)

    @Synchronized
    fun snapshotAll(): List<VoiceCircuitRecord> = records.values.toList()

    @Synchronized
    fun reset(key: VoiceCircuitKey) {
        records.remove(key)
    }

    private fun currentForGeneration(key: VoiceCircuitKey, generation: String): VoiceCircuitRecord {
        val current = records[key] ?: VoiceCircuitRecord(key = key, generation = generation)
        if (generation.isNotBlank() && current.generation.isNotBlank() && current.generation != generation) {
            return VoiceCircuitRecord(key = key, generation = generation).also { records[key] = it }
        }
        if (current.generation.isBlank() && generation.isNotBlank()) {
            return current.copy(generation = generation).also { records[key] = it }
        }
        return current
    }

    private fun thresholdFor(kind: VoiceFailureKind): Int = when (kind) {
        VoiceFailureKind.OUT_OF_MEMORY,
        VoiceFailureKind.MODEL_VERIFICATION -> 1
        VoiceFailureKind.NATIVE_CRASH -> config.nativeCrashThreshold
        VoiceFailureKind.THERMAL_PRESSURE -> config.thermalFailureThreshold
        VoiceFailureKind.TIMEOUT -> config.timeoutFailureThreshold
        VoiceFailureKind.PROVIDER_PROTOCOL,
        VoiceFailureKind.AGENT_PROTOCOL,
        VoiceFailureKind.TTS_UNDERRUN -> config.protocolFailureThreshold
        else -> config.transientFailureThreshold
    }.coerceAtLeast(1)

    private fun openDurationFor(kind: VoiceFailureKind): Long = when (kind) {
        VoiceFailureKind.OUT_OF_MEMORY -> config.outOfMemoryOpenMs
        VoiceFailureKind.NATIVE_CRASH,
        VoiceFailureKind.MODEL_VERIFICATION -> config.nativeOpenMs
        VoiceFailureKind.THERMAL_PRESSURE -> config.thermalOpenMs
        VoiceFailureKind.TIMEOUT -> config.timeoutOpenMs
        else -> config.defaultOpenMs
    }.coerceAtLeast(1L)

    private fun sanitizeReason(value: String): String = value
        .trim()
        .lowercase()
        .replace(Regex("[^a-z0-9_.:-]+"), "_")
        .trim('_')
        .take(96)
}
