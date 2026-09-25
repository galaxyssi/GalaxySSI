package com.galaxyssi.glasses

import android.content.Context
import java.io.File

/** Single-session CPU runtime for the bundled multilingual Whisper Tiny Q5_1 model. */
internal object WhisperTinyNative {
    private const val MODEL_NAME = "ggml-tiny-q5_1.bin"
    private const val MODEL_SIZE = 32152673L
    init { System.loadLibrary("arwhisper") }

    private var handle = 0L

    fun prepareModel(context: Context): File {
        val target = File(context.filesDir, MODEL_NAME)
        if (target.length() == MODEL_SIZE) return target
        val partial = File(context.filesDir, "$MODEL_NAME.partial")
        context.assets.open(MODEL_NAME).use { input ->
            partial.outputStream().use { output -> input.copyTo(output) }
        }
        check(partial.length() == MODEL_SIZE) { "Whisper Tiny model copy is incomplete" }
        if (target.exists()) check(target.delete()) { "Whisper Tiny old model could not be replaced" }
        check(partial.renameTo(target)) { "Whisper Tiny model could not be saved" }
        return target
    }

    @Synchronized fun load(model: File) {
        if (handle != 0L) return
        require(model.isFile) { "Whisper Tiny model is missing" }
        handle = nativeLoad(model.absolutePath)
        check(handle != 0L) { "Whisper Tiny model could not be loaded" }
    }

    @Synchronized fun transcribe(pcm: ShortArray): String {
        check(handle != 0L) { "Whisper Tiny model is not ready" }
        return nativeTranscribe(handle, pcm, 4).trim()
    }

    @Synchronized fun close() {
        if (handle != 0L) nativeFree(handle)
        handle = 0L
    }

    private external fun nativeLoad(path: String): Long
    private external fun nativeTranscribe(handle: Long, pcm: ShortArray, threads: Int): String
    private external fun nativeFree(handle: Long)
}
