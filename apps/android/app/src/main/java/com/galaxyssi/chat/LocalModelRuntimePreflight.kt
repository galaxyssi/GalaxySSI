package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import okhttp3.HttpUrl.Companion.toHttpUrl
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
    ACCELERATOR_UNAVAILABLE,
    THERMAL_PRESSURE,
    DEVICE_TOO_HOT,
    LOW_BATTERY,
    CRITICAL_BATTERY,
    POWER_SAVE_MODE
}

enum class LocalModelArtifactFormat {
    GGUF,
    QAIRT
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
    val quantizationLabel: String,
    val repositoryId: String = "",
    val fileName: String = "",
    val sha256: String = "",
    val parameterCountBillions: Double = 0.0,
    val defaultNoThink: Boolean = false,
    val visionCapable: Boolean = false,
    val preferredAccelerator: LocalModelAcceleratorKind = LocalModelAcceleratorKind.CPU,
    val sourceTrust: LocalModelSourceTrust = LocalModelSourceTrust.CURATED,
    val sourceHub: LocalModelHubSource = LocalModelHubSource.HUGGING_FACE,
    val artifactFormat: LocalModelArtifactFormat = LocalModelArtifactFormat.GGUF,
    val targetChipset: String = ""
) {
    val downloadable: Boolean
        get() = repositoryId.matches(REPOSITORY_PATTERN) && expectedModelFileBytes > 0L && when (artifactFormat) {
            LocalModelArtifactFormat.GGUF -> validArtifactPath(fileName) &&
                sha256.matches(Regex("[a-f0-9]{64}"))
            LocalModelArtifactFormat.QAIRT -> targetChipset.matches(Regex("SM[0-9]{4}"))
        }

    fun sourceUrls(preferChinaMirror: Boolean): List<String> {
        if (!downloadable || artifactFormat != LocalModelArtifactFormat.GGUF) return emptyList()
        val primary = modelUrl("https://huggingface.co/")
        val mirror = modelUrl("https://hf-mirror.com/")
        val modelScope = modelScopeUrl()
        return when {
            sourceHub == LocalModelHubSource.MODELSCOPE -> listOf(modelScope, mirror, primary)
            preferChinaMirror -> listOf(mirror, modelScope, primary)
            else -> listOf(primary, modelScope, mirror)
        }
    }

    private fun modelUrl(baseUrl: String): String = baseUrl.toHttpUrl().newBuilder()
        .addPathSegments(repositoryId)
        .addPathSegment("resolve")
        .addPathSegment("main")
        .addPathSegments(fileName)
        .build()
        .toString()

    private fun modelScopeUrl(): String = "https://modelscope.cn/".toHttpUrl().newBuilder()
        .addPathSegments("api/v1/models")
        .addPathSegments(repositoryId)
        .addPathSegment("repo")
        .addQueryParameter("Revision", "master")
        .addQueryParameter("FilePath", fileName)
        .build()
        .toString()

    companion object {
        private val REPOSITORY_PATTERN = Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")

        private fun validArtifactPath(value: String): Boolean =
            value.endsWith(".gguf", ignoreCase = true) &&
                '\\' !in value &&
                value.split('/').all { segment ->
                    segment.isNotBlank() && segment != "." && segment != ".."
                }
    }
}

enum class LocalModelSourceTrust {
    CURATED,
    HUB_VERIFIED,
    SIGNED_DEPLOYMENT
}

enum class LocalModelHubSource(val displayName: String) {
    HUGGING_FACE("Hugging Face"),
    MODELSCOPE("ModelScope")
}

data class LocalModelRuntimeRequest(
    val profile: LocalModelRuntimeProfile,
    val requestedContextTokens: Int = profile.defaultContextTokens,
    val preferredThreads: Int = 0,
    val modelFileBytes: Long = profile.expectedModelFileBytes,
    val modelFilePresent: Boolean = true,
    val requireModelFile: Boolean = false,
    val acceleratorReady: Boolean = true
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
    val LFM_2_5_2_6B_QAIRT = profile(
        id = Lfm25QnnDeploymentManifest.MODEL_ID,
        displayName = "LFM2.5 2.6B QNN (NPU)",
        repositoryId = Lfm25QnnDeploymentManifest.SOURCE_MODEL_ID,
        fileName = Lfm25QnnDownloadCatalog.ARCHIVE_FILE_NAME,
        expectedModelFileBytes = Lfm25QnnDownloadCatalog.ESTIMATED_ARCHIVE_BYTES,
        sha256 = "",
        parameterCountBillions = 2.6,
        layerCount = 30,
        keyValueHeadCount = 8,
        headDimension = 64,
        defaultContextTokens = Lfm25QnnDeploymentManifest.DEFAULT_CONTEXT_LIMIT,
        maximumContextTokens = Lfm25QnnDeploymentManifest.MAX_CONTEXT_LIMIT,
        quantizationLabel = Lfm25QnnDeploymentManifest.REQUIRED_PRECISION,
        defaultNoThink = true,
        preferredAccelerator = LocalModelAcceleratorKind.VENDOR_SDK,
        artifactFormat = LocalModelArtifactFormat.QAIRT,
        targetChipset = Lfm25QnnDeploymentManifest.TARGET_CHIPSET
    )
    val QWEN_3_1_7B_QNN = profile(
        id = "qwen3-1-7b-qnn",
        displayName = "Qwen3 1.7B QNN (Hybrid)",
        repositoryId = "unsloth/Qwen3-1.7B-GGUF",
        fileName = "Qwen3-1.7B-Q4_0.gguf",
        expectedModelFileBytes = 1_056_782_912L,
        sha256 = "c876f159707a4e4f70e045106c69db15bfc935a4981706fd4f65c6e7ea1e81c5",
        parameterCountBillions = 1.7,
        layerCount = 36,
        keyValueHeadCount = 8,
        headDimension = 128,
        defaultContextTokens = 2_048,
        maximumContextTokens = 32_768,
        quantizationLabel = "Q4_0",
        defaultNoThink = true,
        preferredAccelerator = LocalModelAcceleratorKind.VENDOR_SDK
    )
    val QWEN_3_1_7B_QAIRT = profile(
        id = "qwen3-1-7b-qairt",
        displayName = "Qwen3 1.7B QNN (NPU)",
        repositoryId = "qualcomm/Qwen3-1.7B",
        fileName = "",
        expectedModelFileBytes = 1_761_061_334L,
        sha256 = "",
        parameterCountBillions = 1.7,
        layerCount = 36,
        keyValueHeadCount = 8,
        headDimension = 128,
        defaultContextTokens = 4_096,
        maximumContextTokens = 4_096,
        quantizationLabel = "W4A16",
        defaultNoThink = true,
        preferredAccelerator = LocalModelAcceleratorKind.VENDOR_SDK,
        artifactFormat = LocalModelArtifactFormat.QAIRT,
        targetChipset = "SM8850"
    )
    val GEMMA_4_E4B_QNN = profile(
        id = "gemma-4-e4b-qnn",
        displayName = "Gemma 4 E4B QNN (Hybrid)",
        repositoryId = "unsloth/gemma-4-E4B-it-GGUF",
        fileName = "gemma-4-E4B-it-Q4_0.gguf",
        expectedModelFileBytes = 4_836_002_944L,
        sha256 = "4a403d2e4d80281063e4f517b1c061ded8476b4011a4fc2ba7dbff707075547e",
        parameterCountBillions = 4.0,
        layerCount = 36,
        keyValueHeadCount = 8,
        headDimension = 128,
        defaultContextTokens = 2_048,
        maximumContextTokens = 128_000,
        quantizationLabel = "Q4_0",
        visionCapable = true,
        preferredAccelerator = LocalModelAcceleratorKind.VENDOR_SDK
    )
    val GEMMA_3_1B_Q4 = profile(
        id = "gemma-3-1b-it-q4-k-m",
        displayName = "Gemma 3 1B Instruct",
        repositoryId = "ggml-org/gemma-3-1b-it-GGUF",
        fileName = "gemma-3-1b-it-Q4_K_M.gguf",
        expectedModelFileBytes = 806_058_240L,
        sha256 = "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135",
        parameterCountBillions = 1.0,
        layerCount = 26,
        keyValueHeadCount = 1,
        headDimension = 256,
        maximumContextTokens = 32_768
    )
    val GEMMA_3_4B_Q4 = profile(
        id = "gemma-3-4b-it-q4-k-m",
        displayName = "Gemma 3 4B Instruct",
        repositoryId = "ggml-org/gemma-3-4b-it-GGUF",
        fileName = "gemma-3-4b-it-Q4_K_M.gguf",
        expectedModelFileBytes = 2_489_757_856L,
        sha256 = "882e8d2db44dc554fb0ea5077cb7e4bc49e7342a1f0da57901c0802ea21a0863",
        parameterCountBillions = 4.0,
        layerCount = 34,
        keyValueHeadCount = 4,
        headDimension = 256,
        maximumContextTokens = 128_000,
        visionCapable = true
    )
    val QWEN_3_4B_Q4_K_M = profile(
        id = "qwen3-4b-q4-k-m",
        displayName = "Qwen3 4B",
        repositoryId = "Qwen/Qwen3-4B-GGUF",
        fileName = "Qwen3-4B-Q4_K_M.gguf",
        expectedModelFileBytes = 2_497_280_256L,
        sha256 = "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
        parameterCountBillions = 4.0,
        layerCount = 36,
        keyValueHeadCount = 8,
        headDimension = 128,
        maximumContextTokens = 32_768,
        defaultNoThink = true
    )
    val QWEN_3_8B_Q4_K_M = profile(
        id = "qwen3-8b-q4-k-m",
        displayName = "Qwen3 8B",
        repositoryId = "Qwen/Qwen3-8B-GGUF",
        fileName = "Qwen3-8B-Q4_K_M.gguf",
        expectedModelFileBytes = 5_027_783_488L,
        sha256 = "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
        parameterCountBillions = 8.2,
        layerCount = 36,
        keyValueHeadCount = 8,
        headDimension = 128,
        maximumContextTokens = 32_768,
        defaultNoThink = true
    )
    val QWEN_3_5_9B_Q4_K_M = profile(
        id = "qwen3-5-9b-q4-k-m",
        displayName = "Qwen3.5 9B",
        repositoryId = "bartowski/Qwen_Qwen3.5-9B-GGUF",
        fileName = "Qwen_Qwen3.5-9B-Q4_K_M.gguf",
        expectedModelFileBytes = 6_169_341_984L,
        sha256 = "d784ce9eda1a5a7b51e8f705a9e6310844bf4f173654d115823c775fdea56d43",
        parameterCountBillions = 9.0,
        layerCount = 32,
        keyValueHeadCount = 4,
        headDimension = 256,
        maximumContextTokens = 262_144,
        visionCapable = true
    )
    val GEMMA_3_12B_Q4_K_M = profile(
        id = "gemma-3-12b-it-q4-k-m",
        displayName = "Gemma 3 12B Instruct",
        repositoryId = "ggml-org/gemma-3-12b-it-GGUF",
        fileName = "gemma-3-12b-it-Q4_K_M.gguf",
        expectedModelFileBytes = 7_300_574_976L,
        sha256 = "7bb69bff3f48a7b642355d64a90e481182a7794707b3133890646b1efa778ff5",
        parameterCountBillions = 12.0,
        layerCount = 48,
        keyValueHeadCount = 8,
        headDimension = 256,
        maximumContextTokens = 128_000,
        visionCapable = true
    )
    val LLAMA_3_1_8B_Q4_K_M = profile(
        id = "llama-3-1-8b-instruct-q4-k-m",
        displayName = "Llama 3.1 8B Instruct",
        repositoryId = "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
        fileName = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
        expectedModelFileBytes = 4_920_739_232L,
        sha256 = "7b064f5842bf9532c91456deda288a1b672397a54fa729aa665952863033557c",
        parameterCountBillions = 8.0,
        layerCount = 32,
        keyValueHeadCount = 8,
        headDimension = 128,
        maximumContextTokens = 128_000
    )
    val DEEPSEEK_R1_DISTILL_LLAMA_8B_Q4_K_M = profile(
        id = "deepseek-r1-distill-llama-8b-q4-k-m",
        displayName = "DeepSeek R1 Distill Llama 8B",
        repositoryId = "unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF",
        fileName = "DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
        expectedModelFileBytes = 4_920_737_216L,
        sha256 = "0addb1339a82385bcd973186cd80d18dcc71885d45eabd899781a118d03827d9",
        parameterCountBillions = 8.0,
        layerCount = 32,
        keyValueHeadCount = 8,
        headDimension = 128,
        maximumContextTokens = 128_000
    )

    @Deprecated("Use QWEN_3_8B_Q4_K_M")
    val QWEN_2_5_7B_Q4: LocalModelRuntimeProfile = QWEN_3_8B_Q4_K_M

    val all: List<LocalModelRuntimeProfile> = listOf(
        GEMMA_3_1B_Q4,
        GEMMA_3_4B_Q4,
        LFM_2_5_2_6B_QAIRT,
        QWEN_3_1_7B_QAIRT,
        QWEN_3_1_7B_QNN,
        QWEN_3_4B_Q4_K_M,
        QWEN_3_8B_Q4_K_M,
        GEMMA_4_E4B_QNN,
        QWEN_3_5_9B_Q4_K_M,
        LLAMA_3_1_8B_Q4_K_M,
        DEEPSEEK_R1_DISTILL_LLAMA_8B_Q4_K_M,
        GEMMA_3_12B_Q4_K_M
    )

    fun find(id: String): LocalModelRuntimeProfile =
        all.firstOrNull { it.id == id } ?: QWEN_3_8B_Q4_K_M

    private fun profile(
        id: String,
        displayName: String,
        repositoryId: String,
        fileName: String,
        expectedModelFileBytes: Long,
        sha256: String,
        parameterCountBillions: Double,
        layerCount: Int,
        keyValueHeadCount: Int,
        headDimension: Int,
        defaultContextTokens: Int = 4_096,
        maximumContextTokens: Int,
        quantizationLabel: String = "Q4_K_M",
        defaultNoThink: Boolean = false,
        visionCapable: Boolean = false,
        preferredAccelerator: LocalModelAcceleratorKind = LocalModelAcceleratorKind.CPU,
        artifactFormat: LocalModelArtifactFormat = LocalModelArtifactFormat.GGUF,
        targetChipset: String = ""
    ) = LocalModelRuntimeProfile(
        id = id,
        displayName = displayName,
        expectedModelFileBytes = expectedModelFileBytes,
        layerCount = layerCount,
        keyValueHeadCount = keyValueHeadCount,
        headDimension = headDimension,
        defaultContextTokens = defaultContextTokens,
        maximumContextTokens = maximumContextTokens,
        quantizationLabel = quantizationLabel,
        repositoryId = repositoryId,
        fileName = fileName,
        sha256 = sha256,
        parameterCountBillions = parameterCountBillions,
        defaultNoThink = defaultNoThink,
        visionCapable = visionCapable,
        preferredAccelerator = preferredAccelerator,
        artifactFormat = artifactFormat,
        targetChipset = targetChipset
    )
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
        if (request.profile.preferredAccelerator != LocalModelAcceleratorKind.CPU && !request.acceleratorReady) {
            issues += LocalModelRuntimeIssue.ACCELERATOR_UNAVAILABLE
        }
        if (device.systemLowMemory) {
            issues += LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY
        }

        var threads = if (request.preferredThreads > 0) {
            request.preferredThreads.coerceIn(1, device.cpuCoreCount.coerceAtLeast(1))
        } else {
            minOf(DEFAULT_MAX_THREADS, device.cpuCoreCount.coerceAtLeast(1))
        }
        if (device.thermalStatus.orDefaultThermal() >= THERMAL_STATUS_MODERATE) {
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

        val blocking = issues.any { issue ->
            when (issue) {
                LocalModelRuntimeIssue.INSUFFICIENT_MEMORY ->
                    profile.preferredAccelerator != LocalModelAcceleratorKind.VENDOR_SDK
                else -> issue in setOf(
                    LocalModelRuntimeIssue.MODEL_FILE_MISSING,
                    LocalModelRuntimeIssue.MODEL_FILE_INVALID,
                    LocalModelRuntimeIssue.ACCELERATOR_UNAVAILABLE,
                    LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY,
                    LocalModelRuntimeIssue.DEVICE_TOO_HOT
                )
            }
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
            preferredThreads = preferredThreads,
            acceleratorReady = acceleratorReady(context, profile)
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
                requireModelFile = true,
                acceleratorReady = acceleratorReady(context, profile)
            ),
            LocalModelDeviceSnapshotDetector.capture(context)
        )
    )

    fun beforeLaunchManagedArtifact(
        context: Context,
        profile: LocalModelRuntimeProfile,
        contextTokens: Int,
        preferredThreads: Int = 0
    ): LocalModelRuntimeEstimate = LocalModelRuntimeEstimator.requireLaunchable(
        LocalModelRuntimeEstimator.estimate(
            LocalModelRuntimeRequest(
                profile = profile,
                requestedContextTokens = contextTokens,
                preferredThreads = preferredThreads,
                modelFileBytes = profile.expectedModelFileBytes,
                modelFilePresent = LocalModelManager.isInstalled(context, profile),
                requireModelFile = true,
                acceleratorReady = acceleratorReady(context, profile)
            ),
            LocalModelDeviceSnapshotDetector.capture(context)
        )
    )

    private fun acceleratorReady(context: Context, profile: LocalModelRuntimeProfile): Boolean {
        if (profile.preferredAccelerator == LocalModelAcceleratorKind.CPU) return true
        if (profile.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1
        ) {
            return false
        }
        val detector = LocalModelAcceleratorDetector.detect(context)
        return detector[profile.preferredAccelerator].ready
    }
}

object LocalModelRuntimeSettings {
    fun selectedProfile(context: Context): LocalModelRuntimeProfile =
        LocalModelCatalog.find(
            context,
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getString(KEY_PROFILE, LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M.id)
                .orEmpty()
        )

    fun setSelectedProfile(context: Context, profileId: String) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PROFILE, LocalModelCatalog.find(context, profileId).id)
            .apply()
    }

    fun enabledProfileIds(context: Context): Set<String> {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val profiles = LocalModelCatalog.profiles(context)
        val knownIds = profiles.mapTo(linkedSetOf(), LocalModelRuntimeProfile::id)
        if (preferences.contains(KEY_ENABLED_PROFILES)) {
            return preferences.getStringSet(KEY_ENABLED_PROFILES, emptySet())
                .orEmpty()
                .filterTo(linkedSetOf()) { it in knownIds }
        }
        if (preferences.contains(KEY_ENABLED_QNN_PROFILES)) {
            val legacyEnabled = preferences.getStringSet(KEY_ENABLED_QNN_PROFILES, emptySet())
                .orEmpty()
                .filterTo(linkedSetOf()) { it in knownIds }
            if (legacyEnabled.isNotEmpty()) return legacyEnabled
            return listOf(selectedProfile(context))
                .filter { LocalModelManager.isInstalled(context, it) }
                .mapTo(linkedSetOf(), LocalModelRuntimeProfile::id)
        }
        val installedQnn = profiles
            .filter(LocalModelRuntimeProfile::supportsQnnCooperation)
            .filter { LocalModelManager.isInstalled(context, it) }
            .mapTo(linkedSetOf(), LocalModelRuntimeProfile::id)
        if (installedQnn.isNotEmpty()) return installedQnn
        return listOf(selectedProfile(context))
            .filter { LocalModelManager.isInstalled(context, it) }
            .mapTo(linkedSetOf(), LocalModelRuntimeProfile::id)
    }

    fun enabledQnnProfileIds(context: Context): Set<String> =
        enabledProfileIds(context)
            .filterTo(linkedSetOf()) { id ->
                LocalModelCatalog.find(context, id).supportsQnnCooperation
            }

    fun isProfileEnabled(context: Context, profile: LocalModelRuntimeProfile): Boolean =
        profile.id in enabledProfileIds(context)

    fun setProfileEnabled(context: Context, profile: LocalModelRuntimeProfile, enabled: Boolean) {
        val updated = LocalModelPostInstallSelection.updatedProfiles(
            enabledProfileIds(context),
            profile.id,
            enabled
        )
        val qnnIds = LocalModelCatalog.profiles(context)
            .filter { it.supportsQnnCooperation && it.id in updated }
            .mapTo(linkedSetOf(), LocalModelRuntimeProfile::id)
        val editor = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_ENABLED_PROFILES, updated)
            .putStringSet(KEY_ENABLED_QNN_PROFILES, qnnIds)
        if (enabled) {
            editor.putString(KEY_PROFILE, profile.id)
        } else if (selectedProfile(context).id == profile.id) {
            editor.putString(
                KEY_PROFILE,
                updated.firstOrNull() ?: LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M.id
            )
        }
        editor.apply()
    }

    fun registerInstalledProfile(context: Context, profile: LocalModelRuntimeProfile) {
        setProfileEnabled(context, profile, enabled = true)
    }

    fun removeProfile(context: Context, profile: LocalModelRuntimeProfile) {
        setProfileEnabled(context, profile, enabled = false)
    }

    fun activeProfiles(context: Context): List<LocalModelRuntimeProfile> {
        val selectedId = selectedProfile(context).id
        return LocalModelCatalog.profiles(context)
            .filter { it.id in enabledProfileIds(context) && LocalModelManager.isInstalled(context, it) }
            .sortedByDescending { it.id == selectedId }
    }

    fun displayProfile(context: Context): LocalModelRuntimeProfile {
        val active = activeProfiles(context)
        return active.firstOrNull() ?: selectedProfile(context)
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

    private const val PREFERENCES = "galaxyssi_local_model_runtime_v1"
    private const val KEY_PROFILE = "profile"
    private const val KEY_ENABLED_PROFILES = "enabled_profiles"
    private const val KEY_ENABLED_QNN_PROFILES = "enabled_qnn_profiles"
    private const val KEY_CONTEXT_TOKENS = "context_tokens"
    private const val DEFAULT_CONTEXT_TOKENS = 4_096
    private const val MIN_CONTEXT_TOKENS = 512
    private const val MAX_CONTEXT_TOKENS = 32_768
}

internal val LocalModelRuntimeProfile.supportsQnnCooperation: Boolean
    get() = preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK

internal val LocalModelRuntimeProfile.isQwen17Qnn: Boolean
    get() = id == LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT.id ||
        id == LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id
