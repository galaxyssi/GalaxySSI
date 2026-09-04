package com.galaxyssi.chat.voice.asr.local

internal class LocalAsrRuntimeEnvironmentController(
    private val engine: LocalAsrEngine,
    private val lifecycle: LocalAsrLifecycleCoordinator,
    private val elapsedRealtimeMs: () -> Long,
    private val policyPlanner: AdaptiveAsrRuntimePolicyPlanner = AdaptiveAsrRuntimePolicyPlanner()
) {
    private val lock = Any()
    private var activeSessionToken = 0L
    private var activeConfig: AsrConfig? = null
    private var sessionStartedAtMs = 0L
    private var thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_NONE
    private var systemPowerSaveMode = false
    private var lastPolicy: AsrRuntimePolicy? = null

    fun onEngineStateChanged(state: LocalAsrState) {
        val policy = synchronized(lock) {
            when (state) {
                is LocalAsrState.Starting -> activateLocked(state.sessionToken, state.config)
                is LocalAsrState.Listening -> activateLocked(state.sessionToken, state.config)
                is LocalAsrState.Paused -> activateLocked(state.sessionToken, state.config)
                is LocalAsrState.Stopping -> activateLocked(state.sessionToken, state.config)
                else -> clearSessionLocked()
            }
            resolvePolicyLocked()
        }
        policy?.let(engine::updateRuntimePolicy)
    }

    fun onThermalStatusChanged(status: Int) {
        val normalized = status.coerceIn(
            AsrRuntimePolicy.THERMAL_STATUS_NONE,
            AsrRuntimePolicy.THERMAL_STATUS_SHUTDOWN
        )
        lifecycle.onThermalLimitChanged(normalized >= AsrRuntimePolicy.THERMAL_STATUS_CRITICAL)
        val policy = synchronized(lock) {
            thermalStatus = normalized
            resolvePolicyLocked()
        }
        policy?.let(engine::updateRuntimePolicy)
    }

    fun onSystemPowerSaveModeChanged(enabled: Boolean) {
        val policy = synchronized(lock) {
            systemPowerSaveMode = enabled
            resolvePolicyLocked()
        }
        policy?.let(engine::updateRuntimePolicy)
    }

    fun tick() {
        val policy = synchronized(lock) { resolvePolicyLocked() }
        policy?.let(engine::updateRuntimePolicy)
    }

    fun currentPolicy(): AsrRuntimePolicy? = synchronized(lock) { lastPolicy }

    private fun activateLocked(sessionToken: Long, config: AsrConfig) {
        if (activeSessionToken != sessionToken) {
            activeSessionToken = sessionToken
            sessionStartedAtMs = elapsedRealtimeMs().coerceAtLeast(0L)
        }
        activeConfig = config
    }

    private fun clearSessionLocked() {
        activeSessionToken = 0L
        activeConfig = null
        sessionStartedAtMs = 0L
        lastPolicy = null
    }

    private fun resolvePolicyLocked(): AsrRuntimePolicy? {
        val config = activeConfig ?: return null
        val elapsed = (elapsedRealtimeMs().coerceAtLeast(0L) - sessionStartedAtMs).coerceAtLeast(0L)
        val policy = policyPlanner.resolve(config, elapsed, thermalStatus, systemPowerSaveMode)
        if (policy == lastPolicy) return null
        lastPolicy = policy
        return policy
    }
}
