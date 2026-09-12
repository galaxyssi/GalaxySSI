package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class KnowledgeSourcePreviewCipherTest {
    @Test fun keyOwnershipEndsOnCloseAndHasShortOperationLifetime() {
        val key = ByteArray(32) { (it + 1).toByte() }
        val cipher = KnowledgeSourcePreviewCipher(key, 10)
        assertFalse(cipher.expired(30_009)); assertTrue(cipher.expired(30_010))
        cipher.close(); assertTrue(key.all { it == 0.toByte() }); assertTrue(cipher.expired(10))
        assertThrows(IllegalStateException::class.java) { cipher.encrypt(byteArrayOf(1), byteArrayOf(2)) }
    }
    @Test fun distinctNoncesAuthenticateContentAndAssociatedIdentity() {
        KnowledgeSourcePreviewCipher(ByteArray(32) { 7 }, 0).use { cipher ->
            val message = "source metadata".toByteArray(); val aad = "namespace:id:hash".toByteArray()
            val first = cipher.encrypt(message, aad); val next = cipher.encrypt(message, aad)
            assertFalse(first.contentEquals(next)); assertArrayEquals(message, cipher.decrypt(first, aad))
            assertThrows(Exception::class.java) { cipher.decrypt(first, "other source".toByteArray()) }
            val corrupt = first.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
            assertThrows(Exception::class.java) { cipher.decrypt(corrupt, aad) }
            assertThrows(Exception::class.java) { cipher.decrypt(first.copyOf(20), aad) }
        }
    }
    @Test fun keyAndEnvelopeVersionCannotBeSubstituted() {
        val aad = byteArrayOf(8)
        val first = KnowledgeSourcePreviewCipher(ByteArray(32) { 1 }, 0).use { it.encrypt(byteArrayOf(4), aad) }
        KnowledgeSourcePreviewCipher(ByteArray(32) { 2 }, 0).use {
            assertThrows(Exception::class.java) { it.decrypt(first, aad) }
            assertThrows(Exception::class.java) { it.decrypt(first.copyOf().apply { this[0] = 2 }, aad) }
        }
    }
    @Test fun headerFingerprintUsesLengthFramingAndAllIdentityFields() {
        val base = KnowledgeSourceHeader("a", "bc", "d", 1, "cipher")
        for (other in listOf(base.copy(id = "ab", titleKey = "c"), base.copy(sourceKey = "other"),
            base.copy(updated = 2), base.copy(ciphertext = "other")))
            assertFalse(base.fingerprint().contentEquals(other.fingerprint()))
    }
}
