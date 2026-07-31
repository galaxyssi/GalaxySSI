package com.signalasi.chat

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Base64

@RunWith(AndroidJUnit4::class)
class SecuritySensitiveStateInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun prepare() {
        SignalASILinkProtocol.clear(context)
        AndroidPersistentSignalStore.clear(context)
        AgentEncryptedPreferences(context, TRUST_PREFERENCES).clear()
        SignalASICrypto.initialize(context)
        SignalASICrypto.resetLocalIdentity(context)
    }

    @After
    fun cleanUp() {
        SignalASILinkProtocol.clear(context)
        AndroidPersistentSignalStore.clear(context)
        AgentEncryptedPreferences(context, TRUST_PREFERENCES).clear()
    }

    @Test
    fun routesFingerprintAndGrantAreEncryptedAtRest() {
        val serverRouteId = SignalASILinkProtocol.newRouteId()
        val fingerprint = "f".repeat(64)
        val qr = JSONObject()
            .put("type", "signalasi_verify")
            .put("protocol", SignalASILinkProtocol.NAME)
            .put("version", SignalASILinkProtocol.VERSION)
            .put("role", "server")
            .put("desktop_id", "desktop_encrypted_test")
            .put("desktop_name", "Encrypted test")
            .put("identity_key_sha256", fingerprint)
            .put("server_route_id", serverRouteId)
            .put("pairing_topic", "${SignalASILinkProtocol.TOPIC_ROOT}/$serverRouteId/pair")
            .put("pairing_token", "t".repeat(40))
            .put(
                "pairing_secret",
                Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { 7 })
            )
            .put(
                "pairing_access",
                JSONObject()
                    .put("contract_version", SignalASILinkProtocol.ACCESS_CONTRACT)
                    .put("version", 1)
                    .put("profile", SignalASILinkProtocol.ACCESS_RESTRICTED)
                    .put(
                        "scopes",
                        JSONArray(
                            listOf(
                                SignalASILinkProtocol.SCOPE_AGENT_CHAT,
                                SignalASILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
                                SignalASILinkProtocol.SCOPE_TASK_WORKSPACE
                            )
                        )
                    )
            )
            .put("created_at", System.currentTimeMillis())

        val link = SignalASILinkProtocol.ensureServerLink(context, qr)
        SignalASILinkProtocol.markPaired(context, link.desktopId, qr.getJSONObject("pairing_access"))

        val persisted = rawPreferenceValues(LINK_PREFERENCES)
        assertTrue(persisted.isNotEmpty())
        assertTrue(persisted.all(AgentStorageCipher::isEncrypted))
        assertFalse(persisted.any { it.contains(serverRouteId) })
        assertFalse(persisted.any { it.contains(link.routes.clientRouteId) })
        assertFalse(persisted.any { it.contains(fingerprint) })
        assertEquals(
            link.routes.clientRouteId,
            SignalASILinkProtocol.serverLink(context, link.desktopId)?.routes?.clientRouteId
        )
    }

    @Test
    fun signalIdentitySessionsAndTrustFingerprintsAreEncryptedAtRest() {
        val store = AndroidPersistentSignalStore(context)
        val fingerprint = "e".repeat(64)
        SignalASICrypto.debugSetVerifiedPcFingerprint(context, fingerprint)

        val signalValues = rawPreferenceValues(SIGNAL_PREFERENCES)
        val trustValues = rawPreferenceValues(TRUST_PREFERENCES)
        assertTrue(signalValues.isNotEmpty())
        assertTrue(signalValues.all(AgentStorageCipher::isEncrypted))
        assertTrue(trustValues.all(AgentStorageCipher::isEncrypted))
        assertFalse(signalValues.any { it.contains(store.identityKeyPair.toString()) })
        assertFalse(trustValues.any { it.contains(fingerprint) })
        assertEquals(fingerprint, SignalASICrypto.verifiedPcFingerprint())
    }

    private fun rawPreferenceValues(name: String): List<String> =
        context.getSharedPreferences(name, Context.MODE_PRIVATE)
            .all
            .values
            .mapNotNull { it as? String }

    private companion object {
        const val LINK_PREFERENCES = "signalasi_link_v1"
        const val SIGNAL_PREFERENCES = "signalasi_signal_store"
        const val TRUST_PREFERENCES = "signalasi_signal_trust"
    }
}
