package com.galaxyssi.llama

import android.content.Context

object GalaxySSILlamaRuntime {
    private val lock = Any()
    @Volatile private var initialized = false
    @Volatile private var loadFailure: Throwable? = null

    fun isAvailable(): Boolean = runCatching {
        ensureLibraryLoaded()
        true
    }.getOrDefault(false)

    fun initialize(context: Context) {
        ensureLibraryLoaded()
        synchronized(lock) {
            if (!initialized) {
                nativeInitialize(context.applicationInfo.nativeLibraryDir)
                initialized = true
            }
        }
    }

    fun loadModel(
        context: Context,
        modelPath: String,
        contextTokens: Int,
        threads: Int
    ) {
        initialize(context)
        check(nativeLoadModel(modelPath, contextTokens, threads) == 0) {
            "llama.cpp could not load the selected GGUF model"
        }
    }

    fun generate(
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int = 768,
        temperature: Float = 0.3f
    ): String {
        check(initialized) { "llama.cpp is not initialized" }
        return nativeGenerate(
            systemPrompt,
            userPrompt,
            maximumTokens.coerceIn(1, 2_048),
            temperature.coerceIn(0f, 2f)
        )
    }

    fun unload() {
        if (!initialized) return
        nativeUnload()
    }

    fun systemInfo(): String = if (initialized) nativeSystemInfo() else ""

    fun backendInfo(): String = if (initialized) nativeBackendInfo() else ""

    fun osExposesSme(): Boolean {
        ensureLibraryLoaded()
        return nativeOsExposesSme()
    }

    private fun ensureLibraryLoaded() {
        loadFailure?.let { throw IllegalStateException("llama.cpp native runtime is unavailable", it) }
        if (libraryLoaded) return
        synchronized(lock) {
            if (libraryLoaded) return
            try {
                System.loadLibrary("galaxyssi-llama")
                libraryLoaded = true
            } catch (error: Throwable) {
                loadFailure = error
                throw error
            }
        }
    }

    private external fun nativeInitialize(nativeLibraryDirectory: String)
    private external fun nativeLoadModel(modelPath: String, contextTokens: Int, threads: Int): Int
    private external fun nativeGenerate(
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        temperature: Float
    ): String
    private external fun nativeUnload()
    private external fun nativeSystemInfo(): String
    private external fun nativeBackendInfo(): String
    private external fun nativeOsExposesSme(): Boolean

    @Volatile private var libraryLoaded = false
}
