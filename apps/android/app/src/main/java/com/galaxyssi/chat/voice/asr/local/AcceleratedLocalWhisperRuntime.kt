package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.util.Log
import com.galaxyssi.chat.VoiceAssistantSettings
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal fun requiresCompactQnnExecution(asrAcceleration: String, asrQnnPackage: String): Boolean =
    asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN && asrQnnPackage.isNotBlank()

class AcceleratedLocalWhisperRuntime(
    context: Context,
    private val qnnFactory: () -> LocalWhisperRuntime = { QnnWhisperRuntime(context.applicationContext) },
    private val fallbackFactory: () -> LocalWhisperRuntime = { DefaultLocalWhisperRuntime(context.applicationContext) },
    private val qnnEligible: (WhisperModelProfile) -> Boolean = {
        VoiceAssistantSettings.get(context.applicationContext).asrAcceleration ==
            VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
            WhisperQnnSupport.canUse(context.applicationContext, it)
    }
) : LocalWhisperRuntime {
    private val appContext = context.applicationContext
    private val mutableState = MutableStateFlow<WhisperRuntimeState>(WhisperRuntimeState.Unloaded)
    private var active: LocalWhisperRuntime? = null

    override val state: StateFlow<WhisperRuntimeState> = mutableState.asStateFlow()

    override suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions): WhisperLoadedModel {
        val current = active
        val ready = current?.state?.value as? WhisperRuntimeState.Ready
        val wantsQnn = qnnEligible(profile)
        val compactQnnWasExplicitlySelected = VoiceAssistantSettings.get(appContext).let {
            requiresCompactQnnExecution(it.asrAcceleration, it.asrQnnPackage)
        }
        if (ready?.model?.profile?.id == profile.id &&
            (ready.model.accelerationBackend == WhisperAccelerationBackend.QNN_HTP) == wantsQnn
        ) return ready.model
        current?.unload(UnloadReason.MODEL_SWITCH)
        current?.close()
        active = null
        mutableState.value = WhisperRuntimeState.Loading(profile.id)

        if (wantsQnn) {
            val qnn = qnnFactory()
            try {
                val loaded = qnn.load(profile, options)
                active = qnn
                mutableState.value = WhisperRuntimeState.Ready(loaded)
                return loaded
            } catch (error: Throwable) {
                qnn.close()
                if (compactQnnWasExplicitlySelected) {
                    mutableState.value = WhisperRuntimeState.Failed(
                        WhisperRuntimeError(
                            if (error is OutOfMemoryError) {
                                NativeWhisperCode.OUT_OF_MEMORY
                            } else {
                                NativeWhisperCode.MODEL_NOT_LOADED
                            },
                            error.message.orEmpty()
                        )
                    )
                    throw error
                }
                Log.w(TAG, "QNN HTP unavailable; falling back to GGML for ${profile.id}", error)
            }
        }

        return try {
            val fallback = fallbackFactory()
            val loaded = fallback.load(profile, options)
            active = fallback
            mutableState.value = WhisperRuntimeState.Ready(loaded)
            loaded
        } catch (error: Throwable) {
            mutableState.value = WhisperRuntimeState.Failed(
                WhisperRuntimeError(
                    if (error is OutOfMemoryError) NativeWhisperCode.OUT_OF_MEMORY else NativeWhisperCode.MODEL_NOT_LOADED,
                    error.message.orEmpty()
                )
            )
            throw error
        }
    }

    override suspend fun createSession(config: LocalWhisperSessionConfig): LocalWhisperSession =
        requireNotNull(active) { "A Whisper model must be loaded before creating a session" }
            .createSession(config)

    override suspend fun unload(reason: UnloadReason) {
        active?.unload(reason)
        active?.close()
        active = null
        mutableState.value = WhisperRuntimeState.Unloaded
    }

    override suspend fun runBenchmark(request: BenchmarkRequest): BenchmarkResult =
        requireNotNull(active) { "A Whisper model must be loaded before benchmarking" }
            .runBenchmark(request)

    override fun requestAbortAll(reason: AbortReason) {
        active?.requestAbortAll(reason)
    }

    override fun close() {
        active?.close()
        active = null
        mutableState.value = WhisperRuntimeState.Unloaded
    }

    private companion object {
        const val TAG = "GalaxySSIWhisperAccel"
    }
}
