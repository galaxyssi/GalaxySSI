package com.signalasi.chat

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SecuritySensitiveStateInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun prepare() {
        SignalASILinkProtocol.clear(context)
        AndroidPersistentSignalStore.clear(context)
        AgentEncryptedPreferences(context, TRUST_PREFERENCES).clear()
        AgentEncryptedPreferences(context, PHONE_PAIRING_PREFERENCES).clear()
        SignalASICrypto.initialize(context)
        SignalASICrypto.resetLocalIdentity(context)
    }

    @After
    fun cleanUp() {
        SignalASILinkProtocol.clear(context)
        AndroidPersistentSignalStore.clear(context)
        AgentEncryptedPreferences(context, TRUST_PREFERENCES).clear()
        AgentEncryptedPreferences(context, PHONE_PAIRING_PREFERENCES).clear()
    }

    @Test
    fun routesFingerprintAndGrantAreEncryptedAtRest() {
        val fingerprint = "f".repeat(64)
        val qr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(
                JSONObject()
                    .put("t", "o2")
                    .put("n", "Encrypted test")
                    .put("k", "identity-key")
                    .put("h", fingerprint)
                    .put("c", System.currentTimeMillis() / 1000L)
                    .put("x", SignalASILinkProtocol.newLinkSecret())
                    .put("e", SignalASILinkProtocol.newLinkSecret())
                    .put("a", 0)
            )
        )

        val link = SignalASILinkProtocol.ensureServerLink(context, qr)
        SignalASILinkProtocol.markPaired(context, link.desktopId, qr.getJSONObject("pairing_access"))

        val persisted = rawPreferenceValues(LINK_PREFERENCES)
        assertTrue(persisted.isNotEmpty())
        assertTrue(persisted.all(AgentStorageCipher::isEncrypted))
        assertFalse(persisted.any { it.contains(qr.getString("pairing_secret")) })
        assertFalse(persisted.any { it.contains(link.routes.clientRouteId) })
        assertFalse(persisted.any { it.contains(fingerprint) })
        assertEquals(
            link.routes.clientRouteId,
            SignalASILinkProtocol.serverLink(context, link.desktopId)?.routes?.clientRouteId
        )
    }

    @Test
    fun opaquePairingQrVerifiesItsPublicIdentity() {
        val qr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(
                JSONObject()
                    .put("t", "o2")
                    .put("n", "Opaque pairing test")
                    .put("k", SignalASICrypto.localIdentityPublicKey())
                    .put("h", SignalASICrypto.localIdentitySha256())
                    .put("c", System.currentTimeMillis() / 1000L)
                    .put("x", SignalASILinkProtocol.newLinkSecret())
                    .put("e", SignalASILinkProtocol.newLinkSecret())
                    .put("a", 0)
            )
        )

        assertTrue(SignalASICrypto.verifyPcIdentityFromQr(qr.toString()))
        assertEquals(
            qr.getString("identity_key_sha256"),
            SignalASICrypto.verifiedPcFingerprint()
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

    @Test
    fun consumedPhoneQrPreKeyRotatesWithoutChangingIdentity() {
        val store = AndroidPersistentSignalStore(context)
        val identity = store.identityKeyPair.publicKey.serialize()
        val first = store.currentBundleJson("phone", 1)
        val firstPreKeyId = first.getInt("preKeyId")

        store.removePreKey(firstPreKeyId)

        val replacement = store.currentBundleJson("phone", 1)
        val replacementPreKeyId = replacement.getInt("preKeyId")
        assertNotEquals(firstPreKeyId, replacementPreKeyId)
        assertTrue(store.containsPreKey(replacementPreKeyId))
        assertTrue(identity.contentEquals(store.identityKeyPair.publicKey.serialize()))
        assertEquals(first.getString("identityKey"), replacement.getString("identityKey"))
    }

    @Test
    fun phonePairingOfferIsOneTimeAndControlMessagesRejectReplay() {
        val qr = PhoneContactCard.createQr(context, AppStore.profile(context))
        val compact = PhoneContactCard.compactQr(qr)
        val normalized = requireNotNull(PhoneContactCard.normalizeQr(compact))
        assertTrue(compact.toString().toByteArray().size < 1_000)
        assertTrue(PhoneContactCard.isQrOfferValid(normalized))
        assertFalse(normalized.has("signal_bundle"))
        val topic = qr.getString("pairing_topic")
        val token = qr.getString("pairing_token")

        assertTrue(topic in PhoneContactCard.activeRendezvousTopics(context))
        val refreshDelay = requireNotNull(
            PhoneContactCard.nextRendezvousRefreshDelayMillis(context)
        )
        assertTrue(refreshDelay in 1_000L..(PhoneContactCard.CONTROL_MAX_AGE_MILLIS + 1_000L))
        val firstFingerprint = "a".repeat(64)
        assertFalse(
            requireNotNull(
                PhoneContactCard.claimSession(context, topic, token, firstFingerprint)
            ).alreadyClaimed
        )
        assertTrue(topic in PhoneContactCard.activeRendezvousTopics(context))
        assertTrue(
            requireNotNull(
                PhoneContactCard.claimSession(context, topic, token, firstFingerprint)
            ).alreadyClaimed
        )
        assertTrue(PhoneContactCard.claimSession(context, topic, token, "b".repeat(64)) == null)

        val control = PhoneContactCard.controlPayload(
            PhoneContactCard.BUNDLE_RESPONSE_TYPE,
            SignalASICrypto.localSignalasiId(),
            PhoneContactCard.identityCard(context)
        )
        assertTrue(PhoneContactCard.acceptControlMessage(context, control))
        assertFalse(PhoneContactCard.acceptControlMessage(context, control))
    }

    @Test
    fun phoneIdentityCardSignatureDetectsTampering() {
        val card = PhoneContactCard.identityCard(context)
        assertTrue(
            SignalASICrypto.verifyPublicIdentitySignature(
                card.getString("identity_public_key"),
                card.getString("identity_fingerprint"),
                PhoneContactCard.canonicalBytes(card),
                card.getString("signature")
            )
        )

        card.put("name", "Tampered")
        assertFalse(
            SignalASICrypto.verifyPublicIdentitySignature(
                card.getString("identity_public_key"),
                card.getString("identity_fingerprint"),
                PhoneContactCard.canonicalBytes(card),
                card.getString("signature")
            )
        )
    }

    private fun rawPreferenceValues(name: String): List<String> =
        context.getSharedPreferences(name, Context.MODE_PRIVATE)
            .all
            .values
            .mapNotNull { it as? String }

    private companion object {
        const val LINK_PREFERENCES = "opaque_link_v2"
        const val SIGNAL_PREFERENCES = "signalasi_signal_store"
        const val TRUST_PREFERENCES = "signalasi_signal_trust"
        const val PHONE_PAIRING_PREFERENCES = "opaque_phone_pairing_v2"
    }
}
