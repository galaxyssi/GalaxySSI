package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.llama.GalaxySSILlamaRuntime
import java.util.concurrent.atomic.AtomicInteger

data class LocalModelInferenceResult(
    val text: String,
    val profileId: String,
    val backend: String,
    val smeAvailable: Boolean,
    val elapsedMillis: Long,
    val preparationMillis: Long = 0L,
    val totalElapsedMillis: Long = elapsedMillis,
    val timeToFirstTokenMillis: Double = 0.0,
    val promptTokens: Long = 0L,
    val generatedTokens: Long = 0L,
    val prefillTokensPerSecond: Double = 0.0,
    val decodeTokensPerSecond: Double = 0.0,
    val stopReason: String = ""
)

enum class LocalModelThinkingMode {
    AUTOMATIC,
    THINK,
    NO_THINK
}

enum class LocalModelWorkClass {
    INTERACTIVE,
    BACKGROUND
}

class LocalModelBackgroundDeferredException : IllegalStateException(
    "The private local model is reserved for an interactive request"
)

class LocalModelAsrPriorityException : IllegalStateException(
    "Whisper ASR is being kept ready. Choose another model to preserve instant voice input."
)

object LocalModelInferenceRuntime {
    private val lock = Any()
    private val processStartedAtElapsed = monotonicMillis()
    private val foregroundWaiters = AtomicInteger(0)
    @Volatile private var loadedProfile = ""
    @Volatile private var loadedContextTokens = 0
    @Volatile private var foregroundLeaseUntilElapsed =
        processStartedAtElapsed + BACKGROUND_STARTUP_GRACE_MILLIS

    fun available(): Boolean = GalaxySSILlamaRuntime.isAvailable()

    internal fun engineFor(profile: LocalModelRuntimeProfile): LocalModelInferenceEngine =
        if (profile.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK) {
            LocalModelInferenceEngine.GENIEX_NPU
        } else {
            LocalModelInferenceEngine.LEGACY_LLAMA
        }

    internal fun requiresIsolatedProcess(profile: LocalModelRuntimeProfile): Boolean =
        when (engineFor(profile)) {
            LocalModelInferenceEngine.LEGACY_LLAMA,
            LocalModelInferenceEngine.GENIEX_NPU -> true
        }

    fun ready(context: Context): Boolean = LocalModelCooperativeRuntime.ready(context)

    fun ready(context: Context, profile: LocalModelRuntimeProfile): Boolean {
        if (!LocalModelManager.isInstalled(context, profile)) return false
        if (engineFor(profile) == LocalModelInferenceEngine.LEGACY_LLAMA && !available()) return false
        if (engineFor(profile) == LocalModelInferenceEngine.GENIEX_NPU &&
            !LocalModelInferenceProcess.isRuntimeProcess() &&
            SharedQnnRuntimeResources.arbiter.asrHasPriority()
        ) return false
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
        thinkingMode: LocalModelThinkingMode = LocalModelThinkingMode.AUTOMATIC,
        workClass: LocalModelWorkClass = LocalModelWorkClass.INTERACTIVE
    ): LocalModelInferenceResult {
        check(LocalModelRuntimeSettings.isProfileEnabled(context, profile)) {
            "The selected local model is installed but disabled"
        }
        if (workClass == LocalModelWorkClass.BACKGROUND && !backgroundSafe(profile)) {
            throw LocalModelBackgroundDeferredException()
        }
        if (engineFor(profile) == LocalModelInferenceEngine.GENIEX_NPU &&
            !LocalModelInferenceProcess.isRuntimeProcess() &&
            SharedQnnRuntimeResources.arbiter.asrHasPriority()
        ) throw LocalModelAsrPriorityException()
        if (workClass == LocalModelWorkClass.INTERACTIVE) foregroundWaiters.incrementAndGet()
        return try {
            synchronized(lock) {
                if (workClass == LocalModelWorkClass.BACKGROUND && !canRunBackground()) {
                    throw LocalModelBackgroundDeferredException()
                }
                if (requiresIsolatedProcess(profile) && !LocalModelInferenceProcess.isRuntimeProcess()) {
                    GalaxySSILlamaRuntime.unload()
                    GenieXLocalModelRuntime.release()
                    loadedProfile = ""
                    loadedContextTokens = 0
                    return@synchronized LocalModelInferenceProcessClient.generate(
                        context = context.applicationContext,
                        profile = profile,
                        systemPrompt = systemPrompt,
                        userPrompt = userPrompt,
                        maximumTokens = maximumTokens,
                        temperature = temperature,
                        thinkingMode = thinkingMode,
                        workClass = workClass
                    )
                }
                generateLocked(
                    context = context.applicationContext,
                    profile = profile,
                    systemPrompt = systemPrompt,
                    userPrompt = userPrompt,
                    maximumTokens = maximumTokens,
                    temperature = temperature,
                    thinkingMode = thinkingMode
                )
            }
        } finally {
            if (workClass == LocalModelWorkClass.INTERACTIVE) {
                foregroundLeaseUntilElapsed = monotonicMillis() + FOREGROUND_IDLE_GRACE_MILLIS
                foregroundWaiters.decrementAndGet()
            }
        }
    }

    private fun generateLocked(
        context: Context,
        profile: LocalModelRuntimeProfile,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        temperature: Float,
        thinkingMode: LocalModelThinkingMode
    ): LocalModelInferenceResult {
        val engine = engineFor(profile)
        if (engine == LocalModelInferenceEngine.GENIEX_NPU) {
            GalaxySSILlamaRuntime.unload()
            loadedProfile = ""
            loadedContextTokens = 0
            if (GenieXLocalModelRuntime.loadedProfileId().let { it.isNotBlank() && it != profile.id }) {
                GenieXLocalModelRuntime.release()
            }
        } else if (GenieXLocalModelRuntime.loadedProfileId().isNotBlank()) {
            GenieXLocalModelRuntime.release()
        }
        val modelFile = if (profile.artifactFormat == LocalModelArtifactFormat.GGUF) {
            LocalModelManager.verifiedFile(context, profile)
        } else {
            null
        }
        val configuredContext = LocalModelRuntimeSettings.contextTokens(context)
        val requestedContext = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            val manifest = Lfm25QnnDeploymentStore(context).runtimeArtifact(profile).manifest
            LocalModelQnnMemoryPolicy.requireLaunchable(
                profile = profile,
                manifest = manifest,
                requestedContextTokens = configuredContext,
                availableBytes = LocalModelDeviceSnapshotDetector.capture(context).availableMemoryBytes
            ).effectiveContextTokens
        } else {
            configuredContext
        }
        val estimate = if (modelFile != null) {
            LocalModelRuntimePreflight.beforeLaunch(
                context = context,
                profile = profile,
                modelFile = modelFile,
                contextTokens = requestedContext
            )
        } else {
            LocalModelRuntimePreflight.beforeLaunchManagedArtifact(
                context = context,
                profile = profile,
                contextTokens = requestedContext
            )
        }
        val effectiveContext = estimate.recommendedContextTokens
        if (engine == LocalModelInferenceEngine.GENIEX_NPU) {
            return GenieXLocalModelRuntime.generate(
                context = context,
                profile = profile,
                modelFile = modelFile,
                contextTokens = effectiveContext,
                threads = estimate.recommendedThreads,
                systemPrompt = systemPrompt,
                userPrompt = prepareUserPrompt(profile, userPrompt, thinkingMode),
                maximumTokens = maximumTokens,
                temperature = temperature,
                thinkingEnabled = thinkingEnabled(profile, thinkingMode)
            )
        }
        GenieXLocalModelRuntime.release()
        checkNotNull(modelFile) { "A GGUF file is required by the legacy local-model runtime" }
        if (loadedProfile != profile.id || loadedContextTokens != effectiveContext) {
            GalaxySSILlamaRuntime.unload()
            GalaxySSILlamaRuntime.loadModel(
                context = context,
                modelPath = modelFile.absolutePath,
                contextTokens = effectiveContext,
                threads = estimate.recommendedThreads
            )
            loadedProfile = profile.id
            loadedContextTokens = effectiveContext
        }
        val effectivePrompt = prepareUserPrompt(profile, userPrompt, thinkingMode)
        val startedAt = System.currentTimeMillis()
        val reply = GalaxySSILlamaRuntime.generate(
            systemPrompt = systemPrompt,
            userPrompt = effectivePrompt,
            maximumTokens = maximumTokens,
            temperature = temperature
        ).trim()
        check(reply.isNotBlank()) { "The local model returned an empty response" }
        return LocalModelInferenceResult(
            text = reply,
            profileId = profile.id,
            backend = GalaxySSILlamaRuntime.backendInfo(),
            smeAvailable = GalaxySSILlamaRuntime.osExposesSme(),
            elapsedMillis = (System.currentTimeMillis() - startedAt).coerceAtLeast(0L)
        )
    }

    fun canRunBackground(): Boolean =
        foregroundWaiters.get() == 0 && monotonicMillis() >= foregroundLeaseUntilElapsed

    internal fun backgroundSafe(profile: LocalModelRuntimeProfile): Boolean =
        profile.artifactFormat != LocalModelArtifactFormat.QAIRT

    fun releaseForAsr() = synchronized(lock) {
        if (!LocalModelInferenceProcess.isRuntimeProcess()) {
            LocalModelInferenceProcessClient.release()
        }
        GalaxySSILlamaRuntime.unload()
        GenieXLocalModelRuntime.release()
        loadedProfile = ""
        loadedContextTokens = 0
    }

    fun unloadIfSelected(profileId: String) = synchronized(lock) {
        if (loadedProfile == profileId || GenieXLocalModelRuntime.loadedProfileId() == profileId) {
            releaseForAsr()
        }
    }

    fun loadedProfileId(): String = loadedProfile
        .ifBlank(GenieXLocalModelRuntime::loadedProfileId)
        .ifBlank(LocalModelInferenceProcessClient::loadedProfileId)

    fun backendInfo(context: Context): String = runCatching {
        GalaxySSILlamaRuntime.initialize(context.applicationContext)
        GalaxySSILlamaRuntime.backendInfo()
    }.getOrDefault("")

    fun osExposesSme(): Boolean = runCatching(GalaxySSILlamaRuntime::osExposesSme).getOrDefault(false)

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

    private fun monotonicMillis(): Long = System.nanoTime() / NANOSECONDS_PER_MILLISECOND

    private const val BACKGROUND_STARTUP_GRACE_MILLIS = 30_000L
    private const val FOREGROUND_IDLE_GRACE_MILLIS = 30_000L
    private const val NANOSECONDS_PER_MILLISECOND = 1_000_000L
}

internal enum class LocalModelInferenceEngine {
    LEGACY_LLAMA,
    GENIEX_NPU
}
