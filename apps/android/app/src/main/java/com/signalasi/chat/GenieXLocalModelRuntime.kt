package com.signalasi.chat

import android.content.Context
import com.geniex.sdk.GenieXSdk
import com.geniex.sdk.LlmWrapper
import com.geniex.sdk.bean.ChatMessage
import com.geniex.sdk.bean.ComputeUnitValue
import com.geniex.sdk.bean.GenerationConfig
import com.geniex.sdk.bean.LlmCreateInput
import com.geniex.sdk.bean.LlmStreamResult
import com.geniex.sdk.bean.ModelConfig
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object GenieXLocalModelRuntime {
    private var wrapper: LlmWrapper? = null
    private var loadedProfileId = ""
    private var loadedContextTokens = 0
    private var loadedThinkingEnabled = false

    fun generate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        modelFile: File,
        contextTokens: Int,
        threads: Int,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        thinkingEnabled: Boolean
    ): LocalModelInferenceResult = runBlocking {
        check(profile.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK) {
            "GenieX NPU runtime requires a QNN-targeted model profile"
        }
        initialize(context)
        val llm = ensureLoaded(profile, modelFile, contextTokens, threads, thinkingEnabled)
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
        llm.generateStreamFlow(
            templated.formattedText,
            GenerationConfig(maxTokens = maximumTokens.coerceIn(1, 2_048))
        ).collect { event ->
            when (event) {
                is LlmStreamResult.Token -> output.append(event.text)
                is LlmStreamResult.Completed -> Unit
                is LlmStreamResult.Error -> failure = event.throwable
            }
        }
        failure?.let { throw IllegalStateException("GenieX QNN inference failed", it) }
        val reply = output.toString().trim()
        check(reply.isNotBlank()) { "The QNN local model returned an empty response" }
        LocalModelInferenceResult(
            text = reply,
            profileId = profile.id,
            backend = BACKEND_ATTESTATION,
            smeAvailable = false,
            elapsedMillis = (System.currentTimeMillis() - startedAt).coerceAtLeast(0L)
        )
    }

    fun release() = runBlocking {
        releaseLoaded()
    }

    fun loadedProfileId(): String = loadedProfileId

    private suspend fun releaseLoaded() {
        runCatching { wrapper?.stopStream() }
        runCatching { wrapper?.destroy() }
        wrapper = null
        loadedProfileId = ""
        loadedContextTokens = 0
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
        profile: LocalModelRuntimeProfile,
        modelFile: File,
        contextTokens: Int,
        threads: Int,
        thinkingEnabled: Boolean
    ): LlmWrapper {
        wrapper?.takeIf {
            loadedProfileId == profile.id && loadedContextTokens == contextTokens &&
                loadedThinkingEnabled == thinkingEnabled
        }?.let { return it }
        releaseLoaded()
        val created = LlmWrapper.builder()
            .llmCreateInput(
                LlmCreateInput(
                    model_name = profile.repositoryId,
                    model_path = modelFile.absolutePath,
                    config = ModelConfig(
                        nCtx = contextTokens,
                        nThreads = threads,
                        nThreadsBatch = threads,
                        nGpuLayers = -1,
                        max_tokens = 2_048,
                        enable_thinking = thinkingEnabled
                    ),
                    runtime_id = RUNTIME_LLAMA_CPP,
                    compute_unit = ComputeUnitValue.NPU.value
                )
            )
            .build()
            .getOrThrow()
        wrapper = created
        loadedProfileId = profile.id
        loadedContextTokens = contextTokens
        loadedThinkingEnabled = thinkingEnabled
        return created
    }

    private const val RUNTIME_LLAMA_CPP = "llama_cpp"
    private const val BACKEND_ATTESTATION = "GenieX llama.cpp / Hexagon NPU"
}
