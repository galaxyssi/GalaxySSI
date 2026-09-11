package com.galaxyssi.chat

import java.io.Closeable
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

internal class AgentMemoryRecallHasher(generation: String) : Closeable {
    private var mac: Mac? = AgentMemoryIndexKey.deriveRecallKey(generation).let { bytes ->
        try { Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(bytes, "HmacSHA256")) } }
        finally { bytes.fill(0) }
    }
    fun token(value: String): String {
        val input = value.toByteArray(Charsets.UTF_8)
        val digest = try { checkNotNull(mac).doFinal(input) } finally { input.fill(0) }
        return try { Base64.getUrlEncoder().withoutPadding().encodeToString(digest) } finally { digest.fill(0) }
    }
    // Discard JCA's internal key copy; no corpus or long-lived decrypted-key cache is retained.
    override fun close() { mac = null }
}
