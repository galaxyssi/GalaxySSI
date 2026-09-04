package com.galaxyssi.chat.voice.asr.local

import android.os.Build
import android.util.Log

internal interface WhisperNativeApi {
    fun createRuntime(modelPath: String, threadCount: Int, useGpu: Boolean): Long
    fun createSession(runtimeHandle: Long, config: LocalWhisperSessionConfig): Long
    fun decodePcm16(sessionHandle: Long, pcm: ShortArray, offset: Int, length: Int): NativeWhisperResult
    fun requestAbort(sessionHandle: Long)
    fun getTimings(sessionHandle: Long): NativeWhisperTimings
    fun destroySession(sessionHandle: Long)
    fun destroyRuntime(runtimeHandle: Long)
    fun activeRuntimeCount(): Int
    fun activeSessionCount(): Int
}

internal object WhisperNativeBridge : WhisperNativeApi {
    private const val TAG = "GalaxySSIWhisperV2"

    init {
        Log.d(TAG, "Loading Whisper JNI v2 for ${Build.SUPPORTED_ABIS.firstOrNull().orEmpty()}")
        System.loadLibrary("whisper")
    }

    override fun createRuntime(modelPath: String, threadCount: Int, useGpu: Boolean): Long =
        nativeCreateRuntime(modelPath, threadCount, useGpu)

    override fun createSession(runtimeHandle: Long, config: LocalWhisperSessionConfig): Long = nativeCreateSession(
        runtimeHandle,
        config.language,
        config.translate,
        config.noContext,
        config.singleSegment,
        config.maxTokens,
        config.prompt
    )

    override fun decodePcm16(
        sessionHandle: Long,
        pcm: ShortArray,
        offset: Int,
        length: Int
    ): NativeWhisperResult = nativeDecodePcm16(sessionHandle, pcm, offset, length)

    override fun requestAbort(sessionHandle: Long) = nativeRequestAbort(sessionHandle)

    override fun getTimings(sessionHandle: Long): NativeWhisperTimings = nativeGetTimings(sessionHandle)

    override fun destroySession(sessionHandle: Long) = nativeDestroySession(sessionHandle)

    override fun destroyRuntime(runtimeHandle: Long) = nativeDestroyRuntime(runtimeHandle)

    override fun activeRuntimeCount(): Int = nativeActiveRuntimeCount()

    override fun activeSessionCount(): Int = nativeActiveSessionCount()

    private external fun nativeCreateRuntime(modelPath: String, threadCount: Int, useGpu: Boolean): Long
    private external fun nativeCreateSession(
        runtimeHandle: Long,
        language: String,
        translate: Boolean,
        noContext: Boolean,
        singleSegment: Boolean,
        maxTokens: Int,
        prompt: String
    ): Long
    private external fun nativeDecodePcm16(
        sessionHandle: Long,
        pcm: ShortArray,
        offset: Int,
        length: Int
    ): NativeWhisperResult
    private external fun nativeRequestAbort(sessionHandle: Long)
    private external fun nativeGetTimings(sessionHandle: Long): NativeWhisperTimings
    private external fun nativeDestroySession(sessionHandle: Long)
    private external fun nativeDestroyRuntime(runtimeHandle: Long)
    private external fun nativeActiveRuntimeCount(): Int
    private external fun nativeActiveSessionCount(): Int
}
