package com.galaxyssi.chat

import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.*
import org.junit.Test

class AgentBrowserSessionEventCodecTest {
    private val scope = "a".repeat(64)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "first", scope,
        "session", "conversation", "turn", "caller", "workspace", "browser", "page", "handoff", "active")
    private val capability = "c".repeat(64)
    // Produced by Node createHmac/createCipheriv, not by the Android decoder.
    private val golden = "01070707070707070707070707f7172e25060d54b46359992018bfa325027aaa01db703a805b323ef6de8c7ba44bfb6c1a189c040a151fc91a57450f6bf790ca542b87d524c8eb5778e2ab4b3e8eafefe19b4b9eed5b51aa8ed3de319215fda0ebeddc9f14efff8f9835fb6cd8a5c9e91056ca"
        .chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test fun nodeEncryptedEventIsReadableOnlyForItsOriginalBinding() {
        assertEquals("16f6447b93cbf4de6ec5b2175f26996feacf984324fb663cfeb6880a3758994f", record.key)
        assertEquals("session_lost", AgentBrowserSessionEventCodec.decode(record, capability, golden))
        assertNull(AgentBrowserSessionEventCodec.decode(record.copy(generation = "second"), capability, golden))
        assertNull(AgentBrowserSessionEventCodec.decode(record, "b".repeat(64), golden))
        assertNull(AgentBrowserSessionEventCodec.decode(record.copy(handoffId = "other"), capability, golden))
        assertNull(AgentBrowserSessionEventCodec.decode(record.copy(pageId = "other"), capability, golden))
        val other = record.copy(browserSessionId = "other", key = AgentBrowserUserRequest.key(scope, "other"))
        assertNull(AgentBrowserSessionEventCodec.decode(other, capability, golden))
    }

    @Test fun corruptTruncatedOversizedOrUnversionedEventsCannotRetireATask() {
        for (bytes in listOf(golden.copyOf().also { it[it.lastIndex] = (it.last() + 1).toByte() },
            golden.copyOf(20), golden.copyOf().also { it[0] = 2 }, ByteArray(4097))) {
            assertNull(AgentBrowserSessionEventCodec.decode(record, capability, bytes))
        }
    }

    @Test fun evenAuthenticatedPayloadCannotInventBusinessSuccessOrRuntimeDeath() {
        for (code in listOf("returned", "login_success", "browser_runtime_exited", "browser_observation_timeout")) {
            val key = AgentBrowserSessionEventCodec.deriveKey(record, capability)
            val iv = ByteArray(12) { 4 }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
            cipher.updateAAD(AgentBrowserSessionEventCodec.binding(record).toByteArray())
            val plain = "{\"code\":\"$code\",\"session_id\":\"browser\",\"page_id\":\"page\",\"handoff_id\":\"handoff\"}".toByteArray()
            val bytes = byteArrayOf(1) + iv + cipher.doFinal(plain)
            assertNull(AgentBrowserSessionEventCodec.decode(record, capability, bytes))
            key.fill(0); plain.fill(0); bytes.fill(0)
        }
    }

    @Test fun eventFileBindingsRejectTraversalAndMismatchedBrowserIdentity() {
        assertThrows(IllegalArgumentException::class.java) { AgentBrowserSessionEventCodec.binding(record.copy(generation = "../other")) }
        assertThrows(IllegalArgumentException::class.java) { AgentBrowserSessionEventCodec.binding(record.copy(key = "0".repeat(64))) }
    }
}
