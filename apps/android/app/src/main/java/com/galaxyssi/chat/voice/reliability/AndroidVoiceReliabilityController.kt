package com.galaxyssi.chat.voice.reliability

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import com.galaxyssi.chat.BuildConfig
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class VoiceReliabilityAdmission(
    val allowed: Boolean,
    val resource: VoiceResourceDecision,
    val circuit: VoiceCircuitAdmission,
    val rollout: VoiceRolloutDecision,
    val fallbackReasonCode: String = ""
)

class AndroidVoiceReliabilityController(
    context: Context,
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime
) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val thermalController = VoiceThermalController(elapsedRealtime)
    private val resourceGovernor = VoiceResourceGovernor(thermalController = thermalController)
    private val circuitBreaker = VoiceCircuitBreaker(
        elapsedRealtime = elapsedRealtime,
        initialRecords = readCircuitRecords()
    )
    private val stableCohortId = preferences.getString(KEY_COHORT_ID, null)
        ?.takeIf(String::isNotBlank)
        ?: UUID.randomUUID().toString().also { generated ->
            preferences.edit().putString(KEY_COHORT_ID, generated).apply()
        }

    fun admit(
        workload: VoiceWorkloadProfile,
        requestedEnabled: Boolean,
        explicitlyDisabled: Boolean = false,
        deviceCertified: Boolean = !workload.localInference,
        foreground: Boolean = true,
        generation: String = defaultGeneration(workload)
    ): VoiceReliabilityAdmission {
        val key = VoiceCircuitKey(workload.feature, workload.profileId)
        val circuit = circuitBreaker.admit(key, generation)
        val snapshot = snapshot(foreground)
        val resource = resourceGovernor.evaluate(snapshot, workload)
        val rollout = VoiceRolloutPolicy.decide(
            config = VoiceRolloutConfig(
                feature = workload.feature,
                stage = if (isDebuggable()) VoiceRolloutStage.DEVELOPER else VoiceRolloutStage.OPT_IN_BETA,
                requestedEnabled = requestedEnabled,
                explicitlyDisabled = explicitlyDisabled,
                debuggable = isDebuggable(),
                betaOptIn = requestedEnabled
            ),
            evidence = VoiceRolloutEvidence(
                privacyReviewed = true,
                securityReviewed = true,
                diagnosticsAvailable = true,
                supportDocumentationAvailable = true,
                deviceCertified = deviceCertified,
                circuitState = circuit.state
            ),
            stableDeviceId = stableCohortId
        )
        val allowed = resource.allowed && circuit.allowed && rollout.enabled
        return VoiceReliabilityAdmission(
            allowed = allowed,
            resource = resource,
            circuit = circuit,
            rollout = rollout,
            fallbackReasonCode = when {
                !resource.allowed -> resource.reasons.firstOrNull()?.name?.lowercase().orEmpty()
                !circuit.allowed -> circuit.reasonCode.ifBlank { "circuit_open" }
                !rollout.enabled -> rollout.reasonCodes.firstOrNull().orEmpty()
                else -> ""
            }
        )
    }

    @Synchronized
    fun reportSuccess(
        feature: VoicePipelineFeature,
        profileId: String = "",
        generation: String = defaultGeneration(feature, profileId)
    ) {
        circuitBreaker.success(VoiceCircuitKey(feature, profileId), generation)
        persistCircuitRecords()
    }

    @Synchronized
    fun reportFailure(
        feature: VoicePipelineFeature,
        profileId: String = "",
        kind: VoiceFailureKind,
        reasonCode: String = "",
        generation: String = defaultGeneration(feature, profileId)
    ) {
        circuitBreaker.failure(VoiceCircuitKey(feature, profileId), kind, reasonCode, generation)
        persistCircuitRecords()
    }

    @Synchronized
    fun reportFailure(
        feature: VoicePipelineFeature,
        profileId: String = "",
        error: Throwable?,
        reasonCode: String = ""
    ) {
        reportFailure(feature, profileId, classify(error, reasonCode), reasonCode.ifBlank {
            error?.javaClass?.simpleName.orEmpty()
        })
    }

    fun dashboard(foreground: Boolean = true): VoicePerformanceDashboardSnapshot {
        val workload = VoiceWorkloadProfile(feature = VoicePipelineFeature.PCM_CAPTURE)
        val resource = resourceGovernor.evaluate(snapshot(foreground), workload)
        val circuits = circuitBreaker.snapshotAll()
        val rollouts = VoicePipelineFeature.entries.map { feature ->
            val circuit = circuits.firstOrNull { it.key.feature == feature }?.state
                ?: VoiceCircuitState.CLOSED
            VoiceRolloutPolicy.decide(
                VoiceRolloutConfig(
                    feature = feature,
                    stage = if (isDebuggable()) VoiceRolloutStage.DEVELOPER else VoiceRolloutStage.OPT_IN_BETA,
                    requestedEnabled = true,
                    debuggable = isDebuggable(),
                    betaOptIn = true
                ),
                VoiceRolloutEvidence(
                    privacyReviewed = true,
                    securityReviewed = true,
                    diagnosticsAvailable = true,
                    supportDocumentationAvailable = true,
                    deviceCertified = true,
                    circuitState = circuit
                ),
                stableCohortId
            )
        }
        return VoicePerformanceDashboard.build(
            generatedAtElapsedMs = elapsedRealtime(),
            diagnostics = VoiceLatencyTelemetry.diagnosticSummary(appContext),
            resource = resource,
            circuits = circuits,
            rollouts = rollouts
        )
    }

    @Synchronized
    fun reset(feature: VoicePipelineFeature, profileId: String = "") {
        circuitBreaker.reset(VoiceCircuitKey(feature, profileId))
        persistCircuitRecords()
    }

    private fun snapshot(foreground: Boolean): VoiceResourceSnapshot {
        val activity = appContext.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        activity?.getMemoryInfo(memory)
        val battery = appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) level * 100 / scale else null
        val batteryStatus = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            batteryStatus == BatteryManager.BATTERY_STATUS_FULL
        val power = appContext.getSystemService(PowerManager::class.java)
        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else PowerManager.THERMAL_STATUS_NONE
        val connectivity = appContext.getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity?.activeNetwork?.let(connectivity::getNetworkCapabilities)
        val networkAvailable = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val networkMetered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
        return VoiceResourceSnapshot(
            elapsedRealtimeMs = elapsedRealtime(),
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L),
            totalMemoryBytes = memory.totalMem.coerceAtLeast(0L),
            currentPssBytes = Debug.getPss().coerceAtLeast(0L) * 1024L,
            lowMemory = memory.lowMemory,
            thermalStatus = thermal,
            batteryPercent = batteryPercent,
            charging = charging,
            foreground = foreground,
            networkAvailable = networkAvailable,
            networkMetered = networkMetered
        )
    }

    private fun classify(error: Throwable?, reasonCode: String): VoiceFailureKind {
        val combined = "${error?.javaClass?.simpleName.orEmpty()} ${error?.message.orEmpty()} $reasonCode".lowercase()
        return when {
            error is OutOfMemoryError || "outofmemory" in combined || "oom" in combined ->
                VoiceFailureKind.OUT_OF_MEMORY
            "sigill" in combined || "sigsegv" in combined || "native_crash" in combined ->
                VoiceFailureKind.NATIVE_CRASH
            "thermal" in combined || "overheat" in combined -> VoiceFailureKind.THERMAL_PRESSURE
            "timeout" in combined || "timed_out" in combined -> VoiceFailureKind.TIMEOUT
            "network" in combined || "socket" in combined || "offline" in combined ->
                VoiceFailureKind.TRANSIENT_NETWORK
            "protocol" in combined || "sequence" in combined || "malformed" in combined ->
                VoiceFailureKind.PROVIDER_PROTOCOL
            "verify" in combined || "sha" in combined -> VoiceFailureKind.MODEL_VERIFICATION
            else -> VoiceFailureKind.UNKNOWN
        }
    }

    private fun defaultGeneration(workload: VoiceWorkloadProfile): String =
        defaultGeneration(workload.feature, workload.profileId)

    private fun defaultGeneration(feature: VoicePipelineFeature, profileId: String): String =
        "${BuildConfig.VERSION_NAME}:${feature.name}:${profileId.trim()}"

    private fun isDebuggable(): Boolean =
        appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private fun persistCircuitRecords() {
        val records = JSONArray().apply {
            circuitBreaker.snapshotAll().forEach { record ->
                put(JSONObject()
                    .put("feature", record.key.feature.name)
                    .put("profile_id", record.key.profileId)
                    .put("state", record.state.name)
                    .put("consecutive_failures", record.consecutiveFailures)
                    .put("failure_window_started_at_ms", record.failureWindowStartedAtMs)
                    .put("opened_at_ms", record.openedAtMs)
                    .put("open_until_ms", record.openUntilMs)
                    .put("last_failure_kind", record.lastFailureKind?.name.orEmpty())
                    .put("last_failure_code", record.lastFailureCode)
                    .put("success_count", record.successCount)
                    .put("failure_count", record.failureCount)
                    .put("generation", record.generation)
                )
            }
        }
        preferences.edit().putString(KEY_CIRCUITS, records.toString()).apply()
    }

    private fun readCircuitRecords(): List<VoiceCircuitRecord> = runCatching {
        val source = JSONArray(preferences.getString(KEY_CIRCUITS, "[]"))
        buildList {
            for (index in 0 until source.length()) {
                val item = source.optJSONObject(index) ?: continue
                val feature = runCatching {
                    VoicePipelineFeature.valueOf(item.optString("feature"))
                }.getOrNull() ?: continue
                val state = runCatching {
                    VoiceCircuitState.valueOf(item.optString("state"))
                }.getOrDefault(VoiceCircuitState.CLOSED)
                val failure = runCatching {
                    VoiceFailureKind.valueOf(item.optString("last_failure_kind"))
                }.getOrNull()
                val now = elapsedRealtime().coerceAtLeast(0L)
                val storedOpenUntil = item.optLong("open_until_ms").coerceAtLeast(0L)
                val staleAcrossBoot = state == VoiceCircuitState.OPEN &&
                    storedOpenUntil - now !in 1L..MAX_PERSISTED_OPEN_MS
                add(VoiceCircuitRecord(
                    key = VoiceCircuitKey(feature, item.optString("profile_id")),
                    state = if (staleAcrossBoot) VoiceCircuitState.CLOSED else state,
                    consecutiveFailures = if (staleAcrossBoot) 0 else
                        item.optInt("consecutive_failures").coerceAtLeast(0),
                    failureWindowStartedAtMs = item.optLong("failure_window_started_at_ms").coerceAtLeast(0L),
                    openedAtMs = item.optLong("opened_at_ms").coerceAtLeast(0L),
                    openUntilMs = if (staleAcrossBoot) 0L else storedOpenUntil,
                    lastFailureKind = failure,
                    lastFailureCode = item.optString("last_failure_code").take(96),
                    successCount = item.optLong("success_count").coerceAtLeast(0L),
                    failureCount = item.optLong("failure_count").coerceAtLeast(0L),
                    generation = item.optString("generation").take(160)
                ))
            }
        }
    }.getOrDefault(emptyList())

    companion object {
        private const val PREFERENCES = "galaxyssi_voice_reliability_v1"
        private const val KEY_CIRCUITS = "circuit_records"
        private const val KEY_COHORT_ID = "cohort_id"
        private const val MAX_PERSISTED_OPEN_MS = 15L * 60_000L
    }
}
