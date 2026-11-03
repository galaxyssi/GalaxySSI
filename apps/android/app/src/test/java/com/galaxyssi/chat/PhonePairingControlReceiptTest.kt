package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class PhonePairingControlReceiptTest {
    private fun payload() = JSONObject().put("type", PhoneContactCard.APPROVAL_TYPE)
        .put("from", "watch").put("to", "phone").put("control_id", UUID.randomUUID().toString())
        .put("contact_card", JSONObject().put("name", "Watch").put("identity_fingerprint", "fingerprint"))

    private fun receipt(payload: JSONObject) = JSONObject().put("type", PhoneContactCard.RECEIPT_TYPE)
        .put("from", payload.getString("to")).put("to", payload.getString("from"))
        .put("ack_control_id", payload.getString("control_id"))
        .put("ack_payload_hash", PhonePairingControlReceipt.payloadHash(payload))

    @Test fun exactReceiptMatchesAfterPersistentQueueReload() {
        val payload = payload()
        assertTrue(PhonePairingControlReceipt.matches(JSONObject(payload.toString()), receipt(payload)))
    }

    @Test fun receiptBindsBothIdentitiesControlIdAndFullPayload() {
        val payload = payload()
        for ((key, value) in listOf("type" to PhoneContactCard.APPROVAL_TYPE, "from" to "other-phone",
            "to" to "other-watch", "ack_control_id" to UUID.randomUUID().toString(),
            "ack_payload_hash" to "0".repeat(64))) {
            assertFalse(key, PhonePairingControlReceipt.matches(payload, receipt(payload).put(key, value)))
        }
        val changed = JSONObject(payload.toString())
        changed.getJSONObject("contact_card").put("name", "Different")
        assertFalse(PhonePairingControlReceipt.matches(changed, receipt(payload)))
    }

    @Test fun lateReceiptCannotRemoveRenewedApproval() {
        val old = payload()
        assertFalse(PhonePairingControlReceipt.matches(payload(), receipt(old)))
    }

    @Test fun receiptNeverRequiresAReceiptOfItsOwn() {
        val receipt = receipt(payload()).put("control_id", UUID.randomUUID().toString())
        assertFalse(PhonePairingControlReceipt.matches(receipt, receipt(receipt)))
    }

    @Test fun hashIsIndependentOfObjectKeyOrderAndBindsNestedData() {
        val first = JSONObject().put("z", 1).put("card", JSONObject().put("b", 2).put("a", "x"))
        val second = JSONObject().put("card", JSONObject().put("a", "x").put("b", 2)).put("z", 1)
        assertEquals(PhonePairingControlReceipt.payloadHash(first), PhonePairingControlReceipt.payloadHash(second))
        second.getJSONObject("card").put("a", "changed")
        assertNotEquals(PhonePairingControlReceipt.payloadHash(first), PhonePairingControlReceipt.payloadHash(second))
    }
}
