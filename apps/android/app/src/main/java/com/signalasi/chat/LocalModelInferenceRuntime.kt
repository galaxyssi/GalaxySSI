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

object LocalModelInferenceRuntime {
    private val lock = Any()
    @Volatile private var loadedProfile = ""
    @Volatile private var loadedContextTokens = 0

    fun available(): Boolean = SignalASILlamaRuntime.isAvailable()

    fun ready(context: Context): Boolean {
        val profile = LocalModelRuntimeSettings.selectedProfile(context)
        return available() && LocalModelManager.isInstalled(context, profile)
    }

    fun generate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int = 768,
        temperature: Float = 0.3f
    ): LocalModelInferenceResult = synchronized(lock) {
        val appContext = context.applicationContext
        runBlocking { LocalWhisperAsr.release() }
        val modelFile = LocalModelManager.verifiedFile(appContext, profile)
        val requestedContext = LocalModelRuntimeSettings.contextTokens(appContext)
        val estimate = LocalModelRuntimePreflight.beforeLaunch(
            context = appContext,
            profile = profile,
            modelFile = modelFile,
            contextTokens = requestedContext
        )
        val effectiveContext = estimate.recommendedContextTokens
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
        val effectivePrompt = prepareUserPrompt(profile, userPrompt)
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
        loadedProfile = ""
        loadedContextTokens = 0
    }

    fun unloadIfSelected(profileId: String) = synchronized(lock) {
        if (loadedProfile == profileId) releaseForAsr()
    }

    fun loadedProfileId(): String = loadedProfile

    fun backendInfo(context: Context): String = runCatching {
        SignalASILlamaRuntime.initialize(context.applicationContext)
        SignalASILlamaRuntime.backendInfo()
    }.getOrDefault("")

    fun osExposesSme(): Boolean = runCatching(SignalASILlamaRuntime::osExposesSme).getOrDefault(false)

    internal fun prepareUserPrompt(profile: LocalModelRuntimeProfile, userPrompt: String): String {
        if (!profile.defaultNoThink || NO_THINK_COMMAND.containsMatchIn(userPrompt)) return userPrompt
        return "$userPrompt\n/no_think"
    }

    private val NO_THINK_COMMAND = Regex("(?m)(^|\\s)/no_think(?=\\s|$)")
}
