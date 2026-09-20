package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import android.util.Base64
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import java.security.MessageDigest
import java.util.UUID

/** Runs in the library's independent test APK, never the installed watch application's data. */
class WatchContactInteropTest {
    @Test fun signedQrApprovalAndBidirectionalSignalMessages() {
        val context = InstrumentationRegistry.getInstrumentation().context
        assertTrue(context.packageName.endsWith(".test"))
        GalaxySSICrypto.initialize(context)
        val contacts = WatchContacts(context, {}, { _, _, _ -> })
        contacts.load()
        val qr = checkNotNull(PhoneContactCard.normalizeQr(JSONObject(contacts.createQr(true))))
        assertTrue(PhoneContactCard.isQrOfferValid(qr))
        val remote = AndroidPersistentSignalStore(context, AgentEncryptedDatabase(context, "remote_${UUID.randomUUID()}"))
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(remote.getIdentityKeyPair().publicKey.serialize())
            .joinToString("") { "%02x".format(it) }
        val remoteId = "galaxyssi:${fingerprint.take(16)}"
        val localId = GalaxySSICrypto.localGalaxySSIId()
        fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
        val card = JSONObject().put("type", PhoneContactCard.IDENTITY_TYPE).put("version", 2)
            .put("galaxyssi_id", remoteId).put("name", "Interop test")
            .put("identity_public_key", b64(remote.getIdentityKeyPair().publicKey.serialize()))
            .put("identity_fingerprint", fingerprint).put("bundle_identity_fingerprint", fingerprint)
            .put("signal_bundle", remote.currentBundleJson(remoteId, 1))
            .put("pairing_token", "").put("pairing_secret", "").put("pairing_topic", "")
            .put("device_id", "test-device").put("created_at", System.currentTimeMillis())
        card.put("signature", b64(remote.getIdentityKeyPair().privateKey.calculateSignature(PhoneContactCard.canonicalBytes(card))))
        val claim = PhoneContactCard.controlPayload(PhoneContactCard.REQUEST_TYPE, localId, card, qr.getString("pairing_token"))
        val topic = qr.getString("pairing_topic")
        // Same authenticated opaque packet Android publishes after scanning the compact QR.
        val sealed = GalaxySSILinkProtocol.sealWirePacket(claim.toString(), qr.getString("pairing_secret"))
        contacts.control(topic, JSONObject(GalaxySSILinkProtocol.openWirePacket(sealed.toByteArray(), qr.getString("pairing_secret"))))
        assertEquals("pending", contacts.person(remoteId)?.status)
        assertTrue(runCatching { contacts.send(remoteId, "not allowed") }.isFailure)
        val routes = checkNotNull(contacts.link(remoteId)).routes
        contacts.control(routes.down, PhoneContactCard.controlPayload(PhoneContactCard.APPROVAL_TYPE, localId, card))
        assertEquals("A remote approval cannot approve an incoming request", "pending", contacts.person(remoteId)?.status)
        contacts.decide(remoteId, false)
        contacts.control(topic, claim)
        assertEquals("Repeated scans must not undo rejection", "rejected", contacts.person(remoteId)?.status)
        val nextQr = checkNotNull(PhoneContactCard.normalizeQr(JSONObject(contacts.createQr(true))))
        contacts.control(nextQr.getString("pairing_topic"), PhoneContactCard.controlPayload(
            PhoneContactCard.REQUEST_TYPE, localId, card, nextQr.getString("pairing_token")))
        contacts.decide(remoteId, true)
        assertEquals("approved", contacts.person(remoteId)?.status)
        contacts.send(remoteId, "Hello from watch")
        val outbox = AgentEncryptedDatabase(context, "watch_peer_outbox")
        val (key, raw) = outbox.entries().first { JSONObject(it.second).optString("peer") == remoteId }
        val wire = JSONObject(JSONObject(raw).getString("wire"))
        val cipher = SessionCipher(remote, SignalProtocolAddress(localId, 1))
        val decoded = JSONObject(String(cipher.decrypt(PreKeySignalMessage(Base64.decode(wire.getString("body"), Base64.NO_WRAP)))))
        assertEquals("Hello from watch", decoded.getJSONObject("payload").getString("content"))
        contacts.stored(remoteId, key, "0".repeat(64))
        assertEquals("queued", contacts.messages(remoteId).single().state)
        contacts.stored(remoteId, key, MqttDeliveryEnvelope.contentHash(wire))
        assertEquals("delivered", contacts.messages(remoteId).single().state)
        val reply = WatchPeerProtocol.outgoing(remoteId, localId, routes.clientRouteId, "Hello from phone")
        val replyEnvelope = GalaxySSILinkProtocol.makeEnvelope(reply, remoteId, localId)
        val encrypted = cipher.encrypt(replyEnvelope.toString().toByteArray())
        val replyWire = JSONObject().put("scheme", "signal").put("from", remoteId).put("to", localId)
            .put("device_id", 1).put("signal_type", "signal").put("message_type", encrypted.type)
            .put("body", b64(encrypted.serialize()))
        val plaintext = checkNotNull(GalaxySSICrypto.decryptEnvelope(replyWire))
        val payload = checkNotNull(GalaxySSILinkProtocol.unwrapEnvelope(plaintext))
        contacts.accept(remoteId, payload); contacts.accept(remoteId, payload)
        assertEquals(2, contacts.messages(remoteId).size)
        assertEquals(1, contacts.person(remoteId)?.unread)
        val reloaded = WatchContacts(context, {}, { _, _, _ -> }); reloaded.load()
        assertEquals("approved", reloaded.person(remoteId)?.status)
        assertEquals("Hello from phone", reloaded.messages(remoteId).last().text)
        reloaded.delete(remoteId)
        assertTrue(runCatching { reloaded.accept(remoteId, payload) }.isFailure)
        assertTrue(reloaded.messages(remoteId).isEmpty())
    }
}
