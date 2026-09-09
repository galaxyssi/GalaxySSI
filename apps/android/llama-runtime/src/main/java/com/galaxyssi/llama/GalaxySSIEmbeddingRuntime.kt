package com.galaxyssi.llama

import android.content.Context
import android.os.Looper
import java.io.Closeable
import java.io.File

/** Independent, caller-owned encoder. Never replaces the chat model or its context. */
class GalaxySSIEmbeddingRuntime private constructor(private var handle: Long) : Closeable {
    @Synchronized
    fun tokenCount(text: String): Int {
        requireWorkerThread()
        check(handle != 0L) { "Embedding runtime is closed" }
        val utf8 = text.toByteArray(Charsets.UTF_8)
        return try { nativeTokenCount(handle, utf8) } finally { utf8.fill(0) }
    }

    @Synchronized
    fun embed(text: String): FloatArray {
        requireWorkerThread()
        check(handle != 0L) { "Embedding runtime is closed" }
        require(text.isNotBlank()) { "Embedding input is empty" }
        val utf8 = text.toByteArray(Charsets.UTF_8)
        return try {
            nativeEmbed(handle, utf8)
        } finally {
            utf8.fill(0)
        }
    }

    @Synchronized
    override fun close() {
        if (handle == 0L) return
        requireWorkerThread()
        nativeClose(handle)
        handle = 0L
    }

    private external fun nativeEmbed(handle: Long, utf8: ByteArray): FloatArray
    private external fun nativeTokenCount(handle: Long, utf8: ByteArray): Int
    private external fun nativeClose(handle: Long)

    companion object {
        fun open(context: Context, model: File, contextTokens: Int = 512, threads: Int = 2): GalaxySSIEmbeddingRuntime {
            requireWorkerThread()
            require(contextTokens in 32..8192) { "Invalid embedding context size" }
            require(threads in 1..64) { "Invalid embedding thread count" }
            require(model.isFile) { "Embedding model file does not exist" }
            GalaxySSILlamaRuntime.initialize(context)
            val path = model.canonicalPath.toByteArray(Charsets.UTF_8)
            val handle = try { nativeOpen(path, contextTokens, threads) } finally { path.fill(0) }
            check(handle != 0L) { "Embedding model could not be opened" }
            return GalaxySSIEmbeddingRuntime(handle)
        }

        private fun requireWorkerThread() {
            check(Looper.myLooper() != Looper.getMainLooper()) { "Embedding operations must run off the UI thread" }
        }

        private external fun nativeOpen(pathUtf8: ByteArray, contextTokens: Int, threads: Int): Long
    }
}
