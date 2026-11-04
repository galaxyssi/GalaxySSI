package com.galaxyssi.chat

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object HealthPrivacyCipher {
    private const val STORE = "AndroidKeyStore"
    private const val ALIAS = "galaxyssi_health_privacy_v1"
    private const val TRANSFORM = "AES/GCM/NoPadding"
    @Volatile private var cached: SecretKey? = null
    @Synchronized private fun key(create: Boolean): SecretKey {
        cached?.let { return it }
        val keys = KeyStore.getInstance(STORE).apply { load(null) }
        (keys.getKey(ALIAS, null) as? SecretKey)?.let { cached = it; return it }
        check(create && !keys.containsAlias(ALIAS)) { "Health privacy key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE).run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true).build())
            generateKey().also { cached = it }
        }
    }
    fun encrypt(plain: ByteArray, aad: ByteArray, createKey: Boolean = false): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM).apply { init(Cipher.ENCRYPT_MODE, key(createKey)); updateAAD(aad) }
        check(cipher.iv.size == 12)
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
    }
    fun decrypt(envelope: ByteArray, aad: ByteArray): ByteArray {
        require(envelope.size >= 29 && envelope[0] == 1.toByte())
        val cipher = Cipher.getInstance(TRANSFORM).apply {
            init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, envelope, 1, 12)); updateAAD(aad)
        }
        return cipher.doFinal(envelope, 13, envelope.size - 13)
    }
}
