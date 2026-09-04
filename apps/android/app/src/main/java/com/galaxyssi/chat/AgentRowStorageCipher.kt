package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Uses a Keystore-wrapped data key so paging encrypted rows does not require one
 * hardware Keystore operation per row.
 */
internal class AgentRowStorageCipher(
    context: Context,
    private val namespace: String
) {
    private val appContext = context.applicationContext

    fun encrypt(plaintext: String, associatedData: ByteArray): String {
        val key = keyCopy(appContext, namespace)
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, KEY_ALGORITHM))
            cipher.updateAAD(associatedData)
            val plaintextBytes = plaintext.toByteArray(Charsets.UTF_8)
            val ciphertext = try {
                cipher.doFinal(plaintextBytes)
            } finally {
                plaintextBytes.fill(0)
            }
            buildString {
                append(PREFIX)
                append(cipher.iv.toBase64())
                append(':')
                append(ciphertext.toBase64())
            }
        } finally {
            key.fill(0)
        }
    }

    fun decrypt(value: String, associatedData: ByteArray): String? {
        if (!value.startsWith(PREFIX)) {
            return AgentStorageCipher.decrypt(value, associatedData)
        }
        val key = keyCopy(appContext, namespace)
        return try {
            runCatching {
                val parts = value.removePrefix(PREFIX).split(':', limit = 2)
                require(parts.size == 2) { "Invalid row storage envelope" }
                val iv = parts[0].fromBase64()
                require(iv.size == IV_BYTES) { "Invalid row storage IV" }
                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    SecretKeySpec(key, KEY_ALGORITHM),
                    GCMParameterSpec(TAG_BITS, iv)
                )
                cipher.updateAAD(associatedData)
                val plaintextBytes = cipher.doFinal(parts[1].fromBase64())
                try {
                    String(plaintextBytes, Charsets.UTF_8)
                } finally {
                    plaintextBytes.fill(0)
                }
            }.getOrNull()
        } finally {
            key.fill(0)
        }
    }

    fun reencryptLegacy(value: String, associatedData: ByteArray): String? {
        if (!AgentStorageCipher.isEncrypted(value)) return null
        val plaintext = AgentStorageCipher.decrypt(value, associatedData) ?: return null
        return encrypt(plaintext, associatedData)
    }

    fun preload() {
        keyCopy(appContext, namespace).fill(0)
    }

    companion object {
        private const val PREFERENCES = "galaxyssi_row_storage_keys_v1"
        private const val PREFIX = "rowenc:v1:"
        private const val KEY_ALGORITHM = "AES"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128
        private const val KEY_BYTES = 32
        private val KEY_LOCK = Any()
        private val keyCache = ConcurrentHashMap<String, ByteArray>()

        fun isEncrypted(value: String): Boolean = value.startsWith(PREFIX)

        fun clearCachedKeys() {
            synchronized(KEY_LOCK) {
                keyCache.values.forEach { it.fill(0) }
                keyCache.clear()
            }
        }

        private fun keyCopy(context: Context, namespace: String): ByteArray =
            synchronized(KEY_LOCK) {
                keyCache[namespace]?.copyOf() ?: loadOrCreateKey(context, namespace).let { key ->
                    keyCache[namespace] = key
                    key.copyOf()
                }
            }

        private fun loadOrCreateKey(context: Context, namespace: String): ByteArray {
            val startedAt = SystemClock.elapsedRealtime()
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val preferenceKey = keyName(namespace)
            val associatedData = "galaxyssi-row-key:$namespace".toByteArray(Charsets.UTF_8)
            preferences.getString(preferenceKey, null)?.let { wrapped ->
                val encoded = AgentStorageCipher.decrypt(wrapped, associatedData)
                    ?: error("Encrypted row storage key could not be unwrapped")
                return Base64.decode(encoded, Base64.NO_WRAP).also { key ->
                    check(key.size == KEY_BYTES) { "Encrypted row storage key has an invalid size" }
                    logSlowKeyLoad(namespace, startedAt, "unwrap")
                }
            }
            val key = ByteArray(KEY_BYTES).also(SecureRandom()::nextBytes)
            val wrapped = AgentStorageCipher.encrypt(key.toBase64(), associatedData)
            check(preferences.edit().putString(preferenceKey, wrapped).commit()) {
                "Encrypted row storage key could not be persisted"
            }
            logSlowKeyLoad(namespace, startedAt, "create")
            return key
        }

        private fun logSlowKeyLoad(namespace: String, startedAt: Long, operation: String) {
            val elapsed = SystemClock.elapsedRealtime() - startedAt
            if (elapsed >= 100L) {
                Log.i(
                    "GalaxySSIStorage",
                    "row_key operation=$operation namespace=$namespace elapsed_ms=$elapsed"
                )
            }
        }

        private fun keyName(namespace: String): String = MessageDigest.getInstance("SHA-256")
            .digest(namespace.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

        private fun ByteArray.toBase64(): String = Base64.encodeToString(this, Base64.NO_WRAP)
        private fun String.fromBase64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
    }
}
