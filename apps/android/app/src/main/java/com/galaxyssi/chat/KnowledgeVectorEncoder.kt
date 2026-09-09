package com.galaxyssi.chat

import android.content.Context
import android.os.Looper
import com.galaxyssi.llama.GalaxySSIEmbeddingRuntime
import java.io.Closeable
import java.io.File
import java.security.MessageDigest

internal data class KnowledgeVectorSpec(val modelSha256: String, val dimensions: Int, val contextTokens: Int) {
    init {
        require(modelSha256.matches(Regex("[0-9a-f]{64}")))
        require(dimensions in 1..8192 && contextTokens in 32..8192)
    }
    val identity: String get() = "gguf-sequence-l2:chunks-v1:$modelSha256:$dimensions:$contextTokens"
}

internal interface KnowledgeVectorEncoder : Closeable {
    val spec: KnowledgeVectorSpec
    fun tokenCount(text: String): Int
    fun embed(text: String): FloatArray
}

internal class LlamaKnowledgeVectorEncoder private constructor(
    override val spec: KnowledgeVectorSpec, private val runtime: GalaxySSIEmbeddingRuntime
) : KnowledgeVectorEncoder {
    override fun tokenCount(text: String) = runtime.tokenCount(text)
    override fun embed(text: String) = runtime.embed(text)
    override fun close() = runtime.close()

    companion object {
        fun open(context: Context, file: File, spec: KnowledgeVectorSpec): LlamaKnowledgeVectorEncoder {
            check(Looper.myLooper() != Looper.getMainLooper()) { "Model verification must run off the UI thread" }
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { stream ->
                val buffer = ByteArray(65536)
                try {
                    while (true) { val n = stream.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
                } finally { buffer.fill(0) }
            }
            check(digest.digest().joinToString("") { "%02x".format(it) } == spec.modelSha256) {
                "Embedding model checksum mismatch"
            }
            return LlamaKnowledgeVectorEncoder(spec, GalaxySSIEmbeddingRuntime.open(context, file, spec.contextTokens))
        }
    }
}
