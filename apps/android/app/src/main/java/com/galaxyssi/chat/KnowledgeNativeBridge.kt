package com.galaxyssi.chat

import androidx.annotation.Keep

/** No callbacks or shared JNIEnv: all calls originate from Kotlin worker threads. */
@Keep
internal object KnowledgeNativeBridge {
    private val loadError = runCatching { System.loadLibrary("galaxyssi_memory_native") }.exceptionOrNull()
    fun requireAvailable() { check(loadError == null) { "Native memory library is unavailable: ${loadError?.javaClass?.simpleName}" } }
    @JvmStatic external fun openIndex(path: String, key: ByteArray, identity: ByteArray, epoch: ByteArray,
        dimensions: Int, shards: Int, cacheBytes: Long, root: FloatArray?): Long
    @JvmStatic external fun checkpoint(handle: Long): ByteArray
    @JvmStatic external fun beginEvent(handle: Long, event: ByteArray, skip: Boolean): ByteArray
    @JvmStatic external fun append(handle: Long, event: ByteArray, metadata: LongArray, values: FloatArray): ByteArray
    @JvmStatic external fun search(handle: Long, query: FloatArray, count: Int, breadth: Int): ByteArray
    @JvmStatic external fun nodeCount(handle: Long): Long
    @JvmStatic external fun cancel(handle: Long)
    @JvmStatic external fun closeIndex(handle: Long)
}
