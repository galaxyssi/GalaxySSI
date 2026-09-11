package com.galaxyssi.chat

import android.util.AtomicFile
import java.io.File
import java.security.SecureRandom

/** Only a disposable derived index and a Keystore-wrapped random key live here. */
internal class KnowledgeNativeFiles(val root: File, modelKey: String, private val epoch: String) {
    private val identity = AgentNativeJsonCodec.sha256("native-memory:v1:$modelKey:$epoch")
    val directory = File(root, "index-$epoch-v1")
    private val keyFile = AtomicFile(File(root, "index-$epoch-v1.key"))
    private val aad = "knowledge-native-key:v1:$identity".toByteArray(Charsets.UTF_8)

    fun open(dimensions: Int, cacheBytes: Long, vector: FloatArray?): Long {
        KnowledgeNativeBridge.requireAvailable()
        check(root.isDirectory || root.mkdirs()) { "Cannot create native memory directory" }
        val key = readKey()
        return try {
            val id = KnowledgeNativeWire.hex(identity, 32)
            KnowledgeNativeBridge.openIndex(directory.absolutePath, key, id, KnowledgeNativeWire.hex(epoch, 16),
                dimensions, SHARDS, cacheBytes, if (directory.exists()) null else requireNotNull(vector))
        } finally { key.fill(0) }
    }
    private fun readKey(): ByteArray {
        if (keyFile.baseFile.exists() || File(keyFile.baseFile.path + ".bak").exists()) {
            val bytes = keyFile.openRead().use { input ->
                val bounded = input.readBytesBounded(61)
                check(bounded.size == 61) { "Invalid native memory wrapped key size" }
                bounded
            }
            return try { AgentStorageCipher.decryptBinary(bytes, aad).also { check(it.size == 32) } } finally { bytes.fill(0) }
        }
        check(!directory.exists()) { "Native memory key is missing; rebuild the derived index explicitly" }
        val key = ByteArray(32).also { SecureRandom().nextBytes(it) }
        try {
            val bytes = AgentStorageCipher.encryptBinary(key, aad)
            try {
                val stream = keyFile.startWrite()
                try { stream.write(bytes); keyFile.finishWrite(stream) } catch (error: Throwable) { keyFile.failWrite(stream); throw error }
            } finally { bytes.fill(0) }
            return key
        } catch (error: Throwable) { key.fill(0); throw error }
    }
    private fun java.io.InputStream.readBytesBounded(max: Int): ByteArray {
        val result = ByteArray(max)
        var count = 0
        try {
            while (count < max) { val n = read(result, count, max - count); if (n < 0) break; count += n }
            check(read() == -1) { "Oversized native memory wrapped key" }
            return result.copyOf(count)
        } finally { result.fill(0) }
    }
    companion object { const val SHARDS = 4 }
}
