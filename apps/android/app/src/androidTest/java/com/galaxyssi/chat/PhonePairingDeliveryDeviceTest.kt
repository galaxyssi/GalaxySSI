package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class PhonePairingDeliveryDeviceTest {
    @Test fun encryptedPendingConfirmationSurvivesLedgerRecreationAndRequiresPeerReceipt() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val namespace = "test-phone-pairing-${UUID.randomUUID()}"
        val preferences = AgentEncryptedPreferences(app, namespace)
        var now = System.currentTimeMillis()
        fun ledger() = PhonePairingDeliveryLedger(
            { JSONObject(preferences.readString("state", "{}")) },
            { preferences.writeString("state", it.toString()) }, { now })
        val secret = GalaxySSILinkProtocol.newLinkSecret()
        val payload = JSONObject().put("type", PhoneContactCard.APPROVAL_TYPE)
            .put("from", "synthetic-a").put("to", "synthetic-b")
            .put("control_id", UUID.randomUUID().toString()).put("time", now)
        try {
            assertTrue(ledger().enqueue("synthetic-topic", secret, payload, "synthetic-fingerprint"))
            val raw = app.getSharedPreferences(namespace, 0).getString("state", "").orEmpty()
            assertFalse(raw.contains(secret))
            assertFalse(raw.contains("synthetic-b"))
            assertEquals(1, ledger().takeDue().size)
            now += 2_000L
            assertEquals(payload.getString("control_id"), ledger().takeDue().single()
                .getJSONObject("payload").getString("control_id"))
            val receipt = JSONObject().put("ack_control_id", payload.getString("control_id"))
                .put("ack_payload_hash", PhonePairingDeliveryLedger.payloadHash(payload))
            assertFalse(ledger().acknowledge("synthetic-c", "synthetic-fingerprint", receipt))
            assertTrue(ledger().acknowledge("synthetic-b", "synthetic-fingerprint", receipt))
            assertNull(ledger().nextDelay())
        } finally {
            preferences.clear()
            app.deleteSharedPreferences(namespace)
        }
    }
}
