package com.galaxyssi.chat

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

internal object AgentMemoryIndexKey {
    private const val ALIAS = "galaxyssi.personal-memory.index.v1"
    @Volatile private var cached: SecretKey? = null

    fun token(material: String): String {
        val bytes = material.toByteArray(Charsets.UTF_8)
        return try {
            Mac.getInstance("HmacSHA256").run {
                init(key())
                doFinal(bytes).joinToString("") { "%02x".format(it) }
            }
        } finally { bytes.fill(0) }
    }

    fun stamp(): String = token("personal-memory-lookup-key-check-v1")

    internal fun deriveRecallKey(generation: String): ByteArray {
        require(runCatching { java.util.UUID.fromString(generation).toString() == generation }.getOrDefault(false))
        val input = "personal-memory-recall-hmac-v1:$generation".toByteArray(Charsets.UTF_8)
        return try { Mac.getInstance("HmacSHA256").run { init(key()); doFinal(input) } }
        finally { input.fill(0) }
    }

    @Synchronized private fun key(): SecretKey {
        cached?.let { return it }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { cached = it; return it }
        check(!store.containsAlias(ALIAS)) { "Personal memory index key is unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY).build())
            generateKey().also { cached = it }
        }
    }

    @Synchronized fun deleteKey() {
        cached = null
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS)
    }
}
