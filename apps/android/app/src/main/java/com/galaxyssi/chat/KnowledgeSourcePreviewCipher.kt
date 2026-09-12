package com.galaxyssi.chat

import android.os.SystemClock
import java.io.Closeable
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Owns one domain-separated derived key, never a process-global plaintext key cache. */
internal class KnowledgeSourcePreviewCipher(private val key: ByteArray,
    private val createdAt: Long = SystemClock.elapsedRealtime()) : Closeable {
    private var closed = false
    init { require(key.size == 32) }
    fun expired(now: Long = SystemClock.elapsedRealtime()) = closed || now - createdAt >= 30_000L
    fun encrypt(plaintext: ByteArray, aad: ByteArray): ByteArray {
        check(!closed)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        check(cipher.iv.size == 12)
        cipher.updateAAD(aad)
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(plaintext)
    }
    fun decrypt(envelope: ByteArray, aad: ByteArray): ByteArray {
        check(!closed)
        require(envelope.size >= 29 && envelope[0] == 1.toByte()) { "Invalid source preview envelope" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, envelope, 1, 12))
        cipher.updateAAD(aad)
        return cipher.doFinal(envelope, 13, envelope.size - 13)
    }
    override fun close() { key.fill(0); closed = true }
}
