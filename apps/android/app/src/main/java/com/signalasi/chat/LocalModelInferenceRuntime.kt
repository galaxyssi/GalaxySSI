package com.signalasi.chat

import android.content.Context
import com.signalasi.llama.SignalASILlamaRuntime
import kotlinx.coroutines.runBlocking

data class LocalModelInferenceResult(
    val text: String,
    val profileId: String,
    val backend: String,
    val smeAvailable: Boolean,
    val elapsedMillis: Long
)

enum class LocalModelThinkingMode {
    AUTOMATIC,
    THINK,
    NO_THINK
}

object LocalModelInferenceRuntime {
    private val lock = Any()
    @Volatile private var loadedProfile = ""
    @Volatile private var loadedContextTokens = 0

    fun available(): Boolean = SignalASILlamaRuntime.isAvailable()

    internal fun engineFor(profile: LocalModelRuntimeProfile): LocalModelInferenceEngine =
        if (profile.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK) {
            LocalModelInferenceEngine.GENIEX_NPU
        } else {
            LocalModelInferenceEngine.LEGACY_LLAMA
        }

    fun ready(context: Context): Boolean = LocalModelCooperativeRuntime.ready(context)

    fun ready(context: Context, profile: LocalModelRuntimeProfile): Boolean {
        if (!LocalModelManager.isInstalled(context, profile)) return false
        if (engineFor(profile) == LocalModelInferenceEngine.LEGACY_LLAMA && !available()) return false
        return runCatching {
            profile.preferredAccelerator == LocalModelAcceleratorKind.CPU ||
                LocalModelAcceleratorDetector.detect(context)[profile.preferredAccelerator].ready
        }.getOrDefault(false)
    }

    fun generate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int = 768,
        temperature: Float = 0.3f,
        thinkingMode: LocalModelThinkingMode = LocalModelThinkingMode.AUTOMATIC
    ): LocalModelInferenceResult = synchronized(lock) {
        val appContext = context.applicationContext
        val modelFile = LocalModelManager.verifiedFile(appContext, profile)
        val requestedContext = LocalModelRuntimeSettings.contextTokens(appContext)
        val estimate = LocalModelRuntimePreflight.beforeLaunch(
            context = appContext,
            profile = profile,
            modelFile = modelFile,
            contextTokens = requestedContext
        )
        val effectiveContext = estimate.recommendedContextTokens
        runBlocking { LocalWhisperAsr.release() }
        if (engineFor(profile) == LocalModelInferenceEngine.GENIEX_NPU) {
            SignalASILlamaRuntime.unload()
            loadedProfile = ""
            loadedContextTokens = 0
            return@synchronized GenieXLocalModelRuntime.generate(
                context = appContext,
                profile = profile,
                modelFile = modelFile,
                contextTokens = effectiveContext,
                threads = estimate.recommendedThreads,
                systemPrompt = systemPrompt,
                userPrompt = prepareUserPrompt(profile, userPrompt, thinkingMode),
                maximumTokens = maximumTokens,
                thinkingEnabled = thinkingEnabled(profile, thinkingMode)
            )
        }
        GenieXLocalModelRuntime.release()
        if (loadedProfile != profile.id || loadedContextTokens != effectiveContext) {
            SignalASILlamaRuntime.unload()
            SignalASILlamaRuntime.loadModel(
                context = appContext,
                modelPath = modelFile.absolutePath,
                contextTokens = effectiveContext,
                threads = estimate.recommendedThreads
            )
            loadedProfile = profile.id
            loadedContextTokens = effectiveContext
        }
        val effectivePrompt = prepareUserPrompt(profile, userPrompt, thinkingMode)
        val startedAt = System.currentTimeMillis()
        val reply = SignalASILlamaRuntime.generate(
            systemPrompt = systemPrompt,
            userPrompt = effectivePrompt,
            maximumTokens = maximumTokens,
            temperature = temperature
        ).trim()
        check(reply.isNotBlank()) { "The local model returned an empty response" }
        LocalModelInferenceResult(
            text = reply,
            profileId = profile.id,
            backend = SignalASILlamaRuntime.backendInfo(),
            smeAvailable = SignalASILlamaRuntime.osExposesSme(),
            elapsedMillis = (System.currentTimeMillis() - startedAt).coerceAtLeast(0L)
        )
    }

    fun releaseForAsr() = synchronized(lock) {
        SignalASILlamaRuntime.unload()
        GenieXLocalModelRuntime.release()
        loadedProfile = ""
        loadedContextTokens = 0
    }

    fun unloadIfSelected(profileId: String) = synchronized(lock) {
        if (loadedProfile == profileId || GenieXLocalModelRuntime.loadedProfileId() == profileId) {
            releaseForAsr()
        }
    }

    fun loadedProfileId(): String = loadedProfile.ifBlank(GenieXLocalModelRuntime::loadedProfileId)

    fun backendInfo(context: Context): String = runCatching {
        SignalASILlamaRuntime.initialize(context.applicationContext)
        SignalASILlamaRuntime.backendInfo()
    }.getOrDefault("")

    fun osExposesSme(): Boolean = runCatching(SignalASILlamaRuntime::osExposesSme).getOrDefault(false)

    internal fun prepareUserPrompt(
        profile: LocalModelRuntimeProfile,
        userPrompt: String,
        thinkingMode: LocalModelThinkingMode = LocalModelThinkingMode.AUTOMATIC
    ): String {
        if (!profile.isQwenFamily) return userPrompt
        if (thinkingMode == LocalModelThinkingMode.AUTOMATIC) {
            if (THINKING_COMMAND.containsMatchIn(userPrompt) || !profile.defaultNoThink) return userPrompt
            return "$userPrompt\n/no_think"
        }
        val withoutCommand = THINKING_COMMAND.replace(userPrompt, " ")
            .replace(Regex("[ \\t]+(?=\\r?$)", RegexOption.MULTILINE), "")
            .trim()
        val command = if (thinkingMode == LocalModelThinkingMode.THINK) "/think" else "/no_think"
        return if (withoutCommand.isBlank()) command else "$withoutCommand\n$command"
    }

    internal fun thinkingEnabled(
        profile: LocalModelRuntimeProfile,
        thinkingMode: LocalModelThinkingMode
    ): Boolean = when (thinkingMode) {
        LocalModelThinkingMode.AUTOMATIC -> !profile.defaultNoThink
        LocalModelThinkingMode.THINK -> true
        LocalModelThinkingMode.NO_THINK -> false
    }

    private val LocalModelRuntimeProfile.isQwenFamily: Boolean
        get() = id.startsWith("qwen", ignoreCase = true) ||
            repositoryId.substringAfterLast('/').startsWith("qwen", ignoreCase = true)

    private val THINKING_COMMAND = Regex("(?m)(^|\\s)/(?:no_)?think(?=\\s|$)")
}

internal enum class LocalModelInferenceEngine {
    LEGACY_LLAMA,
    GENIEX_NPU
}
