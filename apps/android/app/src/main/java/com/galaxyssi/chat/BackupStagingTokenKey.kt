package com.galaxyssi.chat

import java.io.Closeable
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Private to one restore workspace; never changes or replaces the persistent memory index key. */
internal class BackupStagingTokenKey : Closeable {
    private var mac: Mac? = ByteArray(32).also(SecureRandom()::nextBytes).let { bytes ->
        try { Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(bytes, "HmacSHA256")) } }
        finally { bytes.fill(0) }
    }

    fun token(domain: String, value: String): String {
        val input = "${domain.length}:$domain:$value".toByteArray(Charsets.UTF_8)
        val digest = try { checkNotNull(mac) { "Restore index key is closed" }.doFinal(input) } finally { input.fill(0) }
        return try { Base64.getUrlEncoder().withoutPadding().encodeToString(digest) } finally { digest.fill(0) }
    }

    // JCA owns an internal key copy; discard the primitive instead of promising JVM-wide zeroization.
    override fun close() { mac = null }
}
