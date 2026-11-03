package com.galaxyssi.chat

import android.util.Base64
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest
import java.util.UUID

class WatchPairingReceiptDeviceTest {
    private class Rig {
        val context = InstrumentationRegistry.getInstrumentation().context
        val controls = AgentEncryptedDatabase(context, "watch_peer_controls")
        var requests = 0
        var contacts: WatchContacts
        val card: JSONObject
        val id: String
        val local: String
        val claim: JSONObject
        val topic: String

        init {
            check(context.packageName.endsWith(".test"))
            GalaxySSICrypto.initialize(context)
            contacts = reload()
            val remote = AndroidPersistentSignalStore(context, AgentEncryptedDatabase(context, "receipt_${UUID.randomUUID()}"))
            val publicKey = remote.getIdentityKeyPair().publicKey.serialize()
            val fingerprint = MessageDigest.getInstance("SHA-256").digest(publicKey)
                .joinToString("") { "%02x".format(it) }
            id = "galaxyssi:${fingerprint.take(16)}"
            local = GalaxySSICrypto.localGalaxySSIId()
            card = JSONObject().put("type", PhoneContactCard.IDENTITY_TYPE).put("version", PhoneContactCard.VERSION)
                .put("galaxyssi_id", id).put("name", "Receipt test")
                .put("identity_public_key", Base64.encodeToString(publicKey, Base64.NO_WRAP))
                .put("identity_fingerprint", fingerprint).put("bundle_identity_fingerprint", fingerprint)
                .put("signal_bundle", remote.currentBundleJson(id, 1)).put("device_id", "receipt-test")
                .put("pairing_token", "").put("pairing_secret", "").put("pairing_topic", "")
                .put("created_at", System.currentTimeMillis())
            card.put("signature", Base64.encodeToString(remote.getIdentityKeyPair().privateKey
                .calculateSignature(PhoneContactCard.canonicalBytes(card)), Base64.NO_WRAP))
            val qr = checkNotNull(PhoneContactCard.normalizeQr(JSONObject(contacts.createQr(true))))
            topic = qr.getString("pairing_topic")
            claim = PhoneContactCard.controlPayload(PhoneContactCard.REQUEST_TYPE, local, card, qr.getString("pairing_token"))
            contacts.control(topic, claim)
        }

        fun reload() = WatchContacts(context, {}, { _, _, friend -> if (friend) requests++ }).also { it.load() }
        fun pending(type: String) = controls.entries().map { JSONObject(it.second) }
            .filter { it.optString("peer") == id && it.getJSONObject("payload").optString("type") == type }
        fun decision() = pending(PhoneContactCard.APPROVAL_TYPE).single().getJSONObject("payload")
        fun receipt(payload: JSONObject) = PhoneContactCard.controlPayload(PhoneContactCard.RECEIPT_TYPE, local, card)
            .put("ack_control_id", payload.getString("control_id"))
            .put("ack_payload_hash", PhonePairingControlReceipt.payloadHash(payload))
        fun receive(payload: JSONObject) = contacts.control(checkNotNull(contacts.link(id)).routes.down, payload)
        fun clear() = contacts.delete(id)
    }

    @Test fun authenticatedReceiptClearsOnlyMatchingDecisionAndSurvivesRestart() {
        val rig = Rig()
        try {
            rig.contacts.decide(rig.id, true)
            val decision = rig.decision()
            rig.contacts = rig.reload()
            rig.receive(rig.receipt(decision).put("ack_payload_hash", "0".repeat(64)))
            assertEquals(1, rig.pending(PhoneContactCard.APPROVAL_TYPE).size)
            val receipt = rig.receipt(decision)
            rig.receive(receipt)
            assertTrue(rig.pending(PhoneContactCard.APPROVAL_TYPE).isEmpty())
            val count = rig.controls.entries().size
            rig.receive(receipt)
            assertEquals("Receipts must not produce more receipts", count, rig.controls.entries().size)
            rig.contacts = rig.reload()
            assertEquals("approved", rig.contacts.person(rig.id)?.status)
            assertTrue(rig.pending(PhoneContactCard.APPROVAL_TYPE).isEmpty())
            rig.contacts.control(rig.topic, rig.claim)
            val renewed = rig.decision()
            assertNotEquals(decision.getString("control_id"), renewed.getString("control_id"))
            rig.receive(receipt)
            assertEquals(1, rig.pending(PhoneContactCard.APPROVAL_TYPE).size)
            rig.receive(rig.receipt(renewed))
            assertTrue(rig.pending(PhoneContactCard.APPROVAL_TYPE).isEmpty())
        } finally { rig.clear() }
    }

    @Test fun lostClaimReceiptCanBeRegeneratedAfterRestartWithoutAnotherFriendAlert() {
        val rig = Rig()
        try {
            assertEquals(1, rig.requests)
            val first = rig.pending(PhoneContactCard.RECEIPT_TYPE).single().getJSONObject("payload")
            assertTrue(PhonePairingControlReceipt.matches(rig.claim, first))
            rig.controls.removeAll(rig.controls.entries().filter {
                JSONObject(it.second).optString("peer") == rig.id &&
                    JSONObject(it.second).getJSONObject("payload").optString("type") == PhoneContactCard.RECEIPT_TYPE
            }.map { it.first })
            rig.contacts = rig.reload()
            rig.contacts.control(rig.topic, rig.claim)
            assertEquals(1, rig.requests)
            assertEquals("pending", rig.contacts.person(rig.id)?.status)
            assertTrue(PhonePairingControlReceipt.matches(rig.claim,
                rig.pending(PhoneContactCard.RECEIPT_TYPE).single().getJSONObject("payload")))
        } finally { rig.clear() }
    }
}
