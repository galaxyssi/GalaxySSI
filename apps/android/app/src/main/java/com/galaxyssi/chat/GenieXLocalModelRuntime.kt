package com.galaxyssi.chat

import android.content.Context
import com.geniex.sdk.GenieXSdk
import com.geniex.sdk.LlmWrapper
import com.geniex.sdk.bean.ChatMessage
import com.geniex.sdk.bean.ComputeUnitValue
import com.geniex.sdk.bean.GenerationConfig
import com.geniex.sdk.bean.LlmCreateInput
import com.geniex.sdk.bean.LlmStreamResult
import com.geniex.sdk.bean.ModelConfig
import com.geniex.sdk.bean.ProfilingData
import com.geniex.sdk.bean.SamplerConfig
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object GenieXLocalModelRuntime {
    private var wrapper: LlmWrapper? = null
    private var loadedProfileId = ""
    private var loadedContextTokens = 0
    private var loadedThreads = 0
    private var loadedThinkingEnabled = false

    fun generate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File?,
        contextTokens: Int,
        threads: Int,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        temperature: Float,
        thinkingEnabled: Boolean
    ): LocalModelInferenceResult = runBlocking {
        runtimeMutex.withLock {
            val memoryWatchdog = LocalModelRuntimeMemoryWatchdog.start(profile)
            try {
                generateLocked(
                    context = context,
                    profile = profile,
                    modelFile = modelFile,
                    contextTokens = contextTokens,
                    threads = threads,
                    systemPrompt = systemPrompt,
                    userPrompt = userPrompt,
                    maximumTokens = maximumTokens,
                    temperature = temperature,
                    thinkingEnabled = thinkingEnabled
                )
            } finally {
                memoryWatchdog.close()
            }
        }
    }

    private suspend fun generateLocked(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File?,
        contextTokens: Int,
        threads: Int,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        temperature: Float,
        thinkingEnabled: Boolean
    ): LocalModelInferenceResult {
        val requestStartedAt = System.currentTimeMillis()
        check(profile.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK) {
            "GenieX NPU runtime requires a QNN-targeted model profile"
        }
        initialize(context)
        val llm = ensureLoaded(context.applicationContext, profile, modelFile, contextTokens, threads, thinkingEnabled)
        val resetCode = llm.reset()
        check(resetCode == GENIEX_SUCCESS) {
            "GenieX failed to reset the local-model conversation state (code $resetCode)"
        }
        val messages = buildList {
            if (systemPrompt.isNotBlank()) add(ChatMessage("system", systemPrompt))
            add(ChatMessage("user", userPrompt))
        }
        val templated = llm.applyChatTemplate(
            messages.toTypedArray(),
            null,
            thinkingEnabled
        ).getOrThrow()
        val startedAt = System.currentTimeMillis()
        val output = StringBuilder()
        var failure: Throwable? = null
        var completedProfile: ProfilingData? = null
        llm.generateStreamFlow(
            templated.formattedText,
            GenerationConfig(
                maxTokens = maximumTokens.coerceIn(1, 2_048),
                samplerConfig = SamplerConfig(
                    temperature = if (temperature <= 0.0f) GREEDY_TEMPERATURE_SENTINEL else temperature
                )
            )
        ).collect { event ->
            when (event) {
                is LlmStreamResult.Token -> output.append(event.text)
                is LlmStreamResult.Completed -> completedProfile = event.profile
                is LlmStreamResult.Error -> failure = event.throwable
            }
        }
        failure?.let { throw IllegalStateException("GenieX QNN inference failed", it) }
        val reply = output.toString().trim()
        check(reply.isNotBlank()) { "The QNN local model returned an empty response" }
        val finishedAt = System.currentTimeMillis()
        val profiling = completedProfile
        return LocalModelInferenceResult(
            text = reply,
            profileId = profile.id,
            backend = backendAttestation(profile),
            smeAvailable = false,
            elapsedMillis = (finishedAt - startedAt).coerceAtLeast(0L),
            preparationMillis = (startedAt - requestStartedAt).coerceAtLeast(0L),
            totalElapsedMillis = (finishedAt - requestStartedAt).coerceAtLeast(0L),
            timeToFirstTokenMillis = profiling?.ttftMs ?: 0.0,
            promptTokens = profiling?.promptTokens ?: 0L,
            generatedTokens = profiling?.generatedTokens ?: 0L,
            prefillTokensPerSecond = profiling?.prefillSpeed ?: 0.0,
            decodeTokensPerSecond = profiling?.decodingSpeed ?: 0.0,
            stopReason = profiling?.stopReason.orEmpty()
        )
    }

    fun release() = runBlocking {
        runtimeMutex.withLock {
            releaseLoaded()
        }
    }

    fun loadedProfileId(): String = loadedProfileId

    private suspend fun releaseLoaded() {
        runCatching { wrapper?.stopStream() }
        runCatching { wrapper?.destroy() }
        wrapper = null
        loadedProfileId = ""
        loadedContextTokens = 0
        loadedThreads = 0
        loadedThinkingEnabled = false
    }

    private suspend fun initialize(context: Context) {
        suspendCancellableCoroutine { continuation ->
            GenieXSdk.getInstance().init(
                context.applicationContext,
                object : GenieXSdk.InitCallback {
                    override fun onSuccess() {
                        if (continuation.isActive) continuation.resume(Unit)
                    }

                    override fun onFailure(reason: String) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                IllegalStateException("GenieX initialization failed: $reason")
                            )
                        }
                    }
                }
            )
        }
    }

    private suspend fun ensureLoaded(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File?,
        contextTokens: Int,
        threads: Int,
        thinkingEnabled: Boolean
    ): LlmWrapper {
        val runtimeContextTokens = if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            QAIRT_FIXED_RUNTIME_VALUE
        } else {
            contextTokens
        }
        val runtimeThreads = if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            QAIRT_FIXED_RUNTIME_VALUE
        } else {
            threads
        }
        wrapper?.takeIf {
            loadedProfileId == profile.id && loadedContextTokens == runtimeContextTokens &&
                loadedThreads == runtimeThreads &&
                loadedThinkingEnabled == thinkingEnabled
        }?.let { return it }
        releaseLoaded()
        val artifact = resolveArtifact(context, profile, modelFile)
        val modelConfig = if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            ModelConfig(
                nCtx = 0,
                nGpuLayers = 0,
                max_tokens = 2_048,
                enable_thinking = thinkingEnabled
            )
        } else {
            ModelConfig(
                nCtx = contextTokens,
                nThreads = threads,
                nThreadsBatch = threads,
                nBatch = HYBRID_BATCH_TOKENS,
                nUBatch = HYBRID_BATCH_TOKENS,
                nGpuLayers = -1,
                max_tokens = 2_048,
                enable_thinking = thinkingEnabled
            )
        }
        val created = LlmWrapper.builder()
            .llmCreateInput(
                LlmCreateInput(
                    model_name = artifact.modelName,
                    model_path = artifact.modelPath,
                    tokenizer_path = artifact.tokenizerPath,
                    config = modelConfig,
                    runtime_id = artifact.runtimeId,
                    compute_unit = artifact.computeUnit
                )
            )
            .build()
            .getOrThrow()
        wrapper = created
        loadedProfileId = profile.id
        loadedContextTokens = runtimeContextTokens
        loadedThreads = runtimeThreads
        loadedThinkingEnabled = thinkingEnabled
        return created
    }

    private suspend fun resolveArtifact(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File?
    ): RuntimeArtifact = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
        val artifact = Lfm25QnnDeploymentStore(context).runtimeArtifact(profile)
        RuntimeArtifact(
            modelName = profile.repositoryId,
            modelPath = artifact.modelPath,
            tokenizerPath = artifact.tokenizerPath,
            runtimeId = artifact.runtimeId,
            computeUnit = null
        )
    } else if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
        val paths = GenieXQairtModelManager.paths(context, profile)
            ?: throw IllegalStateException("The Qualcomm QAIRT model is not installed")
        RuntimeArtifact(
            modelName = paths.model_name,
            modelPath = paths.model_path,
            tokenizerPath = paths.tokenizer_path,
            runtimeId = paths.runtime_id.ifBlank { RUNTIME_QAIRT },
            computeUnit = null
        )
    } else {
        val file = requireNotNull(modelFile) { "The GGUF model file is not installed" }
        RuntimeArtifact(
            modelName = profile.repositoryId,
            modelPath = file.absolutePath,
            tokenizerPath = null,
            runtimeId = RUNTIME_LLAMA_CPP,
            computeUnit = ComputeUnitValue.HYBRID.value
        )
    }

    private fun backendAttestation(profile: LocalModelRuntimeProfile): String =
        if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            "GenieX QAIRT / precompiled W4A8 context / Hexagon NPU"
        } else if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            "GenieX QAIRT / Hexagon NPU"
        } else {
            "GenieX llama.cpp / Hexagon hybrid"
        }

    private data class RuntimeArtifact(
        val modelName: String,
        val modelPath: String,
        val tokenizerPath: String?,
        val runtimeId: String,
        val computeUnit: String?
    )

    private const val RUNTIME_LLAMA_CPP = "llama_cpp"
    private const val RUNTIME_QAIRT = "qairt"
    private const val GENIEX_SUCCESS = 0
    private const val HYBRID_BATCH_TOKENS = 128
    private const val QAIRT_FIXED_RUNTIME_VALUE = 0
    private const val GREEDY_TEMPERATURE_SENTINEL = -1.0f
    private val runtimeMutex = Mutex()
}
