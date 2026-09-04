package com.galaxyssi.chat

import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Deterministic transport material bound to both verified Signal identity keys. */
internal object PhoneRelationshipIdentityBinding {
    private val fingerprintPattern = Regex("^[a-fA-F0-9]{64}$")

    fun deriveLinkSecret(
        sharedSecret: ByteArray,
        firstFingerprint: String,
        secondFingerprint: String
    ): String {
        require(sharedSecret.size >= 32) { "Signal identity agreement is too short" }
        val binding = canonicalBinding(firstFingerprint, secondFingerprint)
        return b64Url(hmac(sharedSecret, "galaxyssi-phone-link-v3\u0000$binding".toByteArray()))
    }

    fun deriveRouteId(
        linkSecret: String,
        firstFingerprint: String,
        secondFingerprint: String
    ): String {
        require(GalaxySSILinkProtocol.validLinkSecret(linkSecret)) { "Invalid phone link secret" }
        val binding = canonicalBinding(firstFingerprint, secondFingerprint)
        val key = Base64.getUrlDecoder().decode(linkSecret)
        return b64Url(
            hmac(key, "galaxyssi-phone-route-v3\u0000$binding".toByteArray()).copyOf(16)
        )
    }

    private fun canonicalBinding(firstFingerprint: String, secondFingerprint: String): String {
        require(fingerprintPattern.matches(firstFingerprint)) { "Invalid first identity fingerprint" }
        require(fingerprintPattern.matches(secondFingerprint)) { "Invalid second identity fingerprint" }
        require(!firstFingerprint.equals(secondFingerprint, ignoreCase = true)) {
            "Phone relationship identities must differ"
        }
        return listOf(firstFingerprint.lowercase(), secondFingerprint.lowercase())
            .sorted()
            .joinToString("\u0000")
    }

    private fun hmac(key: ByteArray, value: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(value)
        }

    private fun b64Url(value: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value)
}
