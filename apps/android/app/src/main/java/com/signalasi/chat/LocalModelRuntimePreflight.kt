package com.signalasi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import java.io.File
import kotlin.math.roundToLong

enum class LocalModelRuntimeReadiness {
    READY,
    CAUTION,
    BLOCKED
}

enum class LocalModelRuntimeIssue {
    MODEL_FILE_MISSING,
    MODEL_FILE_INVALID,
    SYSTEM_LOW_MEMORY,
    INSUFFICIENT_MEMORY,
    CONTEXT_REDUCED,
    THERMAL_PRESSURE,
    DEVICE_TOO_HOT,
    LOW_BATTERY,
    CRITICAL_BATTERY,
    POWER_SAVE_MODE
}

data class LocalModelRuntimeProfile(
    val id: String,
    val displayName: String,
    val expectedModelFileBytes: Long,
    val layerCount: Int,
    val keyValueHeadCount: Int,
    val headDimension: Int,
    val defaultContextTokens: Int,
    val maximumContextTokens: Int,
    val quantizationLabel: String
)

data class LocalModelRuntimeRequest(
    val profile: LocalModelRuntimeProfile,
    val requestedContextTokens: Int = profile.defaultContextTokens,
    val preferredThreads: Int = 0,
    val modelFileBytes: Long = profile.expectedModelFileBytes,
    val modelFilePresent: Boolean = true,
    val requireModelFile: Boolean = false
)

data class LocalModelDeviceSnapshot(
    val totalMemoryBytes: Long,
    val availableMemoryBytes: Long,
    val systemLowMemory: Boolean,
    val cpuCoreCount: Int,
    val batteryPercent: Int?,
    val charging: Boolean,
    val batteryTemperatureCelsius: Double?,
    val thermalStatus: Int?,
    val powerSaveMode: Boolean
)

data class LocalModelRuntimeEstimate(
    val readiness: LocalModelRuntimeReadiness,
    val issues: Set<LocalModelRuntimeIssue>,
    val modelFileBytes: Long,
    val modelResidentBytes: Long,
    val kvCacheBytes: Long,
    val runtimeOverheadBytes: Long,
    val threadOverheadBytes: Long,
    val totalRequiredBytes: Long,
    val safeMemoryBudgetBytes: Long,
    val requestedContextTokens: Int,
    val recommendedContextTokens: Int,
    val recommendedThreads: Int,
    val device: LocalModelDeviceSnapshot
) {
    val launchAllowed: Boolean
        get() = readiness != LocalModelRuntimeReadiness.BLOCKED
}

object LocalModelRuntimeProfiles {
    val GEMMA_3_1B_Q4 = LocalModelRuntimeProfile(
        id = "gemma-3-1b-q4",
        displayName = "Gemma 3 1B Q4",
        expectedModelFileBytes = 820L * MIB,
        layerCount = 26,
        keyValueHeadCount = 1,
        headDimension = 256,
        defaultContextTokens = 4_096,
        maximumContextTokens = 32_768,
        quantizationLabel = "Q4"
    )
    val GEMMA_3_4B_Q4 = LocalModelRuntimeProfile(
        id = "gemma-3-4b-q4",
        displayName = "Gemma 3 4B Q4",
        expectedModelFileBytes = 2_650L * MIB,
        layerCount = 34,
        keyValueHeadCount = 4,
        headDimension = 256,
        defaultContextTokens = 4_096,
        maximumContextTokens = 32_768,
        quantizationLabel = "Q4"
    )
    val QWEN_2_5_7B_Q4 = LocalModelRuntimeProfile(
        id = "qwen-2.5-7b-q4",
        displayName = "Qwen 2.5 7B Q4",
        expectedModelFileBytes = 4_450L * MIB,
        layerCount = 28,
        keyValueHeadCount = 4,
        headDimension = 128,
        defaultContextTokens = 4_096,
        maximumContextTokens = 32_768,
        quantizationLabel = "Q4"
    )

    val all: List<LocalModelRuntimeProfile> = listOf(
        GEMMA_3_1B_Q4,
        GEMMA_3_4B_Q4,
        QWEN_2_5_7B_Q4
    )

    fun find(id: String): LocalModelRuntimeProfile =
        all.firstOrNull { it.id == id } ?: GEMMA_3_4B_Q4

    private const val MIB = 1024L * 1024L
}

object LocalModelRuntimeEstimator {
    fun estimate(
        request: LocalModelRuntimeRequest,
        device: LocalModelDeviceSnapshot
    ): LocalModelRuntimeEstimate {
        val profile = request.profile
        val modelFileBytes = request.modelFileBytes.coerceAtLeast(0L)
        val requestedContext = request.requestedContextTokens.coerceIn(
            MIN_CONTEXT_TOKENS,
            profile.maximumContextTokens.coerceAtLeast(MIN_CONTEXT_TOKENS)
        )
        val issues = linkedSetOf<LocalModelRuntimeIssue>()
        if (request.requireModelFile && !request.modelFilePresent) {
            issues += LocalModelRuntimeIssue.MODEL_FILE_MISSING
        }
        if (modelFileBytes <= 0L) {
            issues += LocalModelRuntimeIssue.MODEL_FILE_INVALID
        }
        if (device.systemLowMemory) {
            issues += LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY
        }

        var threads = if (request.preferredThreads > 0) {
            request.preferredThreads.coerceIn(1, device.cpuCoreCount.coerceAtLeast(1))
        } else {
            minOf(DEFAULT_MAX_THREADS, device.cpuCoreCount.coerceAtLeast(1))
        }
        if (device.powerSaveMode || device.thermalStatus.orDefaultThermal() >= THERMAL_STATUS_MODERATE ||
            (!device.charging && (device.batteryPercent ?: 100) < LOW_BATTERY_PERCENT)
        ) {
            threads = minOf(threads, CONSERVATIVE_MAX_THREADS)
        }

        val safeMemoryBudget = safeMemoryBudget(device)
        val contexts = generateSequence(requestedContext) { current ->
            if (current <= MIN_CONTEXT_TOKENS) null else maxOf(MIN_CONTEXT_TOKENS, current / 2)
        }.distinct().toList()
        val requirements = contexts.associateWith { context ->
            requirement(profile, modelFileBytes, context, threads)
        }
        val recommendedContext = contexts.firstOrNull { context ->
            requirements.getValue(context).total <= safeMemoryBudget
        } ?: MIN_CONTEXT_TOKENS
        val selected = requirements[recommendedContext]
            ?: requirement(profile, modelFileBytes, recommendedContext, threads)

        if (selected.total > safeMemoryBudget) {
            issues += LocalModelRuntimeIssue.INSUFFICIENT_MEMORY
        } else if (recommendedContext < requestedContext) {
            issues += LocalModelRuntimeIssue.CONTEXT_REDUCED
        }

        val thermalStatus = device.thermalStatus.orDefaultThermal()
        val batteryTemperature = device.batteryTemperatureCelsius
        when {
            thermalStatus >= THERMAL_STATUS_SEVERE ||
                (batteryTemperature != null && batteryTemperature >= HOT_BATTERY_CELSIUS) ->
                issues += LocalModelRuntimeIssue.DEVICE_TOO_HOT

            thermalStatus >= THERMAL_STATUS_MODERATE ||
                (batteryTemperature != null && batteryTemperature >= WARM_BATTERY_CELSIUS) ->
                issues += LocalModelRuntimeIssue.THERMAL_PRESSURE
        }

        val batteryPercent = device.batteryPercent
        if (!device.charging && batteryPercent != null) {
            when {
                batteryPercent < CRITICAL_BATTERY_PERCENT ->
                    issues += LocalModelRuntimeIssue.CRITICAL_BATTERY
                batteryPercent < LOW_BATTERY_PERCENT ->
                    issues += LocalModelRuntimeIssue.LOW_BATTERY
            }
        }
        if (device.powerSaveMode) {
            issues += LocalModelRuntimeIssue.POWER_SAVE_MODE
        }

        val blocking = issues.any {
            it in setOf(
                LocalModelRuntimeIssue.MODEL_FILE_MISSING,
                LocalModelRuntimeIssue.MODEL_FILE_INVALID,
                LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY,
                LocalModelRuntimeIssue.INSUFFICIENT_MEMORY,
                LocalModelRuntimeIssue.DEVICE_TOO_HOT,
                LocalModelRuntimeIssue.CRITICAL_BATTERY
            )
        }
        val readiness = when {
            blocking -> LocalModelRuntimeReadiness.BLOCKED
            issues.isNotEmpty() -> LocalModelRuntimeReadiness.CAUTION
            else -> LocalModelRuntimeReadiness.READY
        }
        return LocalModelRuntimeEstimate(
            readiness = readiness,
            issues = issues,
            modelFileBytes = modelFileBytes,
            modelResidentBytes = selected.modelResident,
            kvCacheBytes = selected.kvCache,
            runtimeOverheadBytes = selected.runtimeOverhead,
            threadOverheadBytes = selected.threadOverhead,
            totalRequiredBytes = selected.total,
            safeMemoryBudgetBytes = safeMemoryBudget,
            requestedContextTokens = requestedContext,
            recommendedContextTokens = recommendedContext,
            recommendedThreads = threads,
            device = device
        )
    }

    fun requireLaunchable(estimate: LocalModelRuntimeEstimate): LocalModelRuntimeEstimate {
        check(estimate.launchAllowed) {
            "Local model preflight blocked launch: ${estimate.issues.joinToString(",")}"
        }
        return estimate
    }

    private fun requirement(
        profile: LocalModelRuntimeProfile,
        modelFileBytes: Long,
        contextTokens: Int,
        threads: Int
    ): Requirement {
        val modelResident = modelFileBytes +
            maxOf(MIN_MODEL_METADATA_BYTES, (modelFileBytes * MODEL_MAPPING_OVERHEAD_RATIO).roundToLong())
        val kvCache = 2L *
            profile.layerCount.coerceAtLeast(1) *
            contextTokens.coerceAtLeast(MIN_CONTEXT_TOKENS) *
            profile.keyValueHeadCount.coerceAtLeast(1) *
            profile.headDimension.coerceAtLeast(1) *
            KV_CACHE_ELEMENT_BYTES
        val runtimeScratch = (modelFileBytes * RUNTIME_SCRATCH_RATIO).roundToLong()
            .coerceIn(MIN_RUNTIME_SCRATCH_BYTES, MAX_RUNTIME_SCRATCH_BYTES)
        val runtimeOverhead = BASE_RUNTIME_BYTES + runtimeScratch
        val threadOverhead = threads.coerceAtLeast(1) * PER_THREAD_BYTES
        return Requirement(
            modelResident = modelResident,
            kvCache = kvCache,
            runtimeOverhead = runtimeOverhead,
            threadOverhead = threadOverhead,
            total = modelResident + kvCache + runtimeOverhead + threadOverhead
        )
    }

    private fun safeMemoryBudget(device: LocalModelDeviceSnapshot): Long {
        val total = device.totalMemoryBytes.coerceAtLeast(0L)
        val available = device.availableMemoryBytes.coerceIn(0L, total.coerceAtLeast(0L))
        val reserve = maxOf(MIN_SYSTEM_RESERVE_BYTES, (total * SYSTEM_RESERVE_RATIO).roundToLong())
        val totalBound = (total - reserve).coerceAtLeast(0L)
        val availableBound = (available * AVAILABLE_MEMORY_RATIO).roundToLong()
        return minOf(totalBound, availableBound).coerceAtLeast(0L)
    }

    private fun Int?.orDefaultThermal(): Int = this ?: THERMAL_STATUS_NONE

    private data class Requirement(
        val modelResident: Long,
        val kvCache: Long,
        val runtimeOverhead: Long,
        val threadOverhead: Long,
        val total: Long
    )

    private const val MIN_CONTEXT_TOKENS = 512
    private const val DEFAULT_MAX_THREADS = 6
    private const val CONSERVATIVE_MAX_THREADS = 2
    private const val KV_CACHE_ELEMENT_BYTES = 2L
    private const val MODEL_MAPPING_OVERHEAD_RATIO = 0.04
    private const val RUNTIME_SCRATCH_RATIO = 0.08
    private const val SYSTEM_RESERVE_RATIO = 0.18
    private const val AVAILABLE_MEMORY_RATIO = 0.82
    private const val MIN_MODEL_METADATA_BYTES = 64L * 1024L * 1024L
    private const val BASE_RUNTIME_BYTES = 256L * 1024L * 1024L
    private const val MIN_RUNTIME_SCRATCH_BYTES = 128L * 1024L * 1024L
    private const val MAX_RUNTIME_SCRATCH_BYTES = 768L * 1024L * 1024L
    private const val PER_THREAD_BYTES = 8L * 1024L * 1024L
    private const val MIN_SYSTEM_RESERVE_BYTES = 1024L * 1024L * 1024L
    private const val THERMAL_STATUS_NONE = 0
    private const val THERMAL_STATUS_MODERATE = 2
    private const val THERMAL_STATUS_SEVERE = 3
    private const val WARM_BATTERY_CELSIUS = 42.0
    private const val HOT_BATTERY_CELSIUS = 45.0
    private const val LOW_BATTERY_PERCENT = 20
    private const val CRITICAL_BATTERY_PERCENT = 10
}

object LocalModelDeviceSnapshotDetector {
    fun capture(context: Context): LocalModelDeviceSnapshot {
        val appContext = context.applicationContext
        val memoryInfo = ActivityManager.MemoryInfo()
        appContext.getSystemService(ActivityManager::class.java)?.getMemoryInfo(memoryInfo)
        val battery = runCatching {
            appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.getOrNull()
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) {
            ((level.toDouble() / scale.toDouble()) * 100.0).toInt().coerceIn(0, 100)
        } else {
            null
        }
        val batteryStatus = battery?.getIntExtra(
            BatteryManager.EXTRA_STATUS,
            BatteryManager.BATTERY_STATUS_UNKNOWN
        ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN
        val charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            batteryStatus == BatteryManager.BATTERY_STATUS_FULL
        val batteryTemperature = battery
            ?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            ?.takeUnless { it == Int.MIN_VALUE }
            ?.div(10.0)
        val powerManager = appContext.getSystemService(PowerManager::class.java)
        return LocalModelDeviceSnapshot(
            totalMemoryBytes = memoryInfo.totalMem.coerceAtLeast(0L),
            availableMemoryBytes = memoryInfo.availMem.coerceAtLeast(0L),
            systemLowMemory = memoryInfo.lowMemory,
            cpuCoreCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1),
            batteryPercent = batteryPercent,
            charging = charging,
            batteryTemperatureCelsius = batteryTemperature,
            thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                powerManager?.currentThermalStatus
            } else {
                null
            },
            powerSaveMode = powerManager?.isPowerSaveMode == true
        )
    }
}

object LocalModelRuntimePreflight {
    fun estimate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        contextTokens: Int,
        preferredThreads: Int = 0
    ): LocalModelRuntimeEstimate = LocalModelRuntimeEstimator.estimate(
        LocalModelRuntimeRequest(
            profile = profile,
            requestedContextTokens = contextTokens,
            preferredThreads = preferredThreads
        ),
        LocalModelDeviceSnapshotDetector.capture(context)
    )

    fun beforeLaunch(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File,
        contextTokens: Int,
        preferredThreads: Int = 0
    ): LocalModelRuntimeEstimate = LocalModelRuntimeEstimator.requireLaunchable(
        LocalModelRuntimeEstimator.estimate(
            LocalModelRuntimeRequest(
                profile = profile,
                requestedContextTokens = contextTokens,
                preferredThreads = preferredThreads,
                modelFileBytes = modelFile.takeIf(File::isFile)?.length() ?: 0L,
                modelFilePresent = modelFile.isFile,
                requireModelFile = true
            ),
            LocalModelDeviceSnapshotDetector.capture(context)
        )
    )
}

object LocalModelRuntimeSettings {
    fun selectedProfile(context: Context): LocalModelRuntimeProfile =
        LocalModelRuntimeProfiles.find(
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getString(KEY_PROFILE, LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id)
                .orEmpty()
        )

    fun setSelectedProfile(context: Context, profileId: String) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PROFILE, LocalModelRuntimeProfiles.find(profileId).id)
            .apply()
    }

    fun contextTokens(context: Context): Int =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getInt(KEY_CONTEXT_TOKENS, DEFAULT_CONTEXT_TOKENS)
            .coerceIn(MIN_CONTEXT_TOKENS, MAX_CONTEXT_TOKENS)

    fun setContextTokens(context: Context, value: Int) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_CONTEXT_TOKENS, value.coerceIn(MIN_CONTEXT_TOKENS, MAX_CONTEXT_TOKENS))
            .apply()
    }

    private const val PREFERENCES = "signalasi_local_model_runtime_v1"
    private const val KEY_PROFILE = "profile"
    private const val KEY_CONTEXT_TOKENS = "context_tokens"
    private const val DEFAULT_CONTEXT_TOKENS = 4_096
    private const val MIN_CONTEXT_TOKENS = 512
    private const val MAX_CONTEXT_TOKENS = 32_768
}
