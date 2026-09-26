package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class PhonePairingDeliveryTest {
    private class Rig {
        var now = 1_000_000L
        var state = JSONObject()
        fun ledger() = PhonePairingDeliveryLedger(
            { JSONObject(state.toString()) }, { state = JSONObject(it.toString()) }, { now })
        val secret = GalaxySSILinkProtocol.newLinkSecret()
        fun payload(peer: String = "peer-b", type: String = PhoneContactCard.APPROVAL_TYPE) = JSONObject()
            .put("type", type).put("to", peer).put("from", "peer-a")
            .put("control_id", UUID.randomUUID().toString()).put("time", now)
        fun enqueue(ledger: PhonePairingDeliveryLedger, payload: JSONObject) =
            ledger.enqueue("topic", secret, payload, "fingerprint-b")
        fun receipt(payload: JSONObject) = JSONObject()
            .put("ack_control_id", payload.getString("control_id"))
            .put("ack_payload_hash", PhonePairingDeliveryLedger.payloadHash(payload))
    }

    @Test fun lostControlRetriesWithTheSameIdAfterProcessRestart() {
        val rig = Rig()
        val payload = rig.payload()
        assertTrue(rig.enqueue(rig.ledger(), payload))
        val first = rig.ledger().takeDue().single()
        assertEquals(payload.getString("control_id"), first.getJSONObject("payload").getString("control_id"))
        assertTrue(rig.ledger().takeDue().isEmpty())
        rig.now += 2_000
        val retry = rig.ledger().takeDue().single()
        assertEquals(first.getString("hash"), retry.getString("hash"))
        assertTrue(rig.ledger().acknowledge("peer-b", "fingerprint-b", rig.receipt(payload)))
        assertNull(rig.ledger().nextDelay())
    }

    @Test fun brokerSubmissionDoesNotClearPendingControl() {
        val rig = Rig()
        rig.enqueue(rig.ledger(), rig.payload())
        rig.ledger().takeDue()
        assertEquals(1, rig.state.getJSONArray("pending").length())
    }

    @Test fun receiptMustMatchPeerIdentityIdAndPayload() {
        val rig = Rig()
        val payload = rig.payload()
        rig.enqueue(rig.ledger(), payload)
        assertFalse(rig.ledger().acknowledge("peer-c", "fingerprint-b", rig.receipt(payload)))
        assertFalse(rig.ledger().acknowledge("peer-b", "fingerprint-c", rig.receipt(payload)))
        assertFalse(rig.ledger().acknowledge("peer-b", "fingerprint-b",
            rig.receipt(payload).put("ack_payload_hash", "0".repeat(64))))
        assertFalse(rig.ledger().acknowledge("peer-b", "fingerprint-b", rig.receipt(rig.payload())))
        assertTrue(rig.ledger().acknowledge("peer-b", "fingerprint-b", rig.receipt(payload)))
        assertFalse(rig.ledger().acknowledge("peer-b", "fingerprint-b", rig.receipt(payload)))
    }

    @Test fun repeatedApprovalIsCoalescedAndRejectSupersedesIt() {
        val rig = Rig()
        repeat(1000) { assertTrue(rig.enqueue(rig.ledger(), rig.payload())) }
        assertEquals(1, rig.state.getJSONArray("pending").length())
        val rejected = rig.payload(type = PhoneContactCard.REJECTION_TYPE)
        rig.enqueue(rig.ledger(), rejected)
        assertEquals(1, rig.state.getJSONArray("pending").length())
        assertEquals(PhoneContactCard.REJECTION_TYPE, rig.ledger().takeDue().single().getString("type"))
    }

    @Test fun controlsAreBoundedAndExpireInsteadOfAccumulatingOffline() {
        val rig = Rig()
        repeat(PhonePairingDeliveryLedger.MAX_PENDING) {
            assertTrue(rig.enqueue(rig.ledger(), rig.payload("peer-$it")))
        }
        assertFalse(rig.enqueue(rig.ledger(), rig.payload("overflow")))
        rig.now += PhoneContactCard.CONTROL_MAX_AGE_MILLIS
        assertTrue(rig.ledger().takeDue().isEmpty())
        assertNull(rig.ledger().nextDelay())
        assertEquals(0, rig.state.getJSONArray("pending").length())
    }

    @Test fun largeBatchRetriesOnlyFourAtATime() {
        val rig = Rig()
        repeat(10) { rig.enqueue(rig.ledger(), rig.payload("peer-$it")) }
        assertEquals(4, rig.ledger().takeDue().size)
        assertEquals(4, rig.ledger().takeDue().size)
        assertEquals(2, rig.ledger().takeDue().size)
        assertTrue(rig.ledger().takeDue().isEmpty())
    }

    @Test fun lostReceiptsCannotTriggerUnlimitedRetries() {
        val rig = Rig()
        rig.enqueue(rig.ledger(), rig.payload())
        var attempts = 0
        repeat(100) {
            attempts += rig.ledger().takeDue().size
            rig.now += 3_000
        }
        assertTrue(attempts <= PhonePairingDeliveryLedger.MAX_ATTEMPTS)
    }

    @Test fun ordinaryBundleAndExplicitRecoveryRemainSeparate() {
        val rig = Rig()
        rig.enqueue(rig.ledger(), rig.payload(type = PhoneContactCard.BUNDLE_RESPONSE_TYPE))
        rig.enqueue(rig.ledger(), rig.payload(type = PhoneContactCard.BUNDLE_RESPONSE_TYPE)
            .put("session_recovery", true))
        assertEquals(2, rig.ledger().takeDue().size)
    }

    @Test fun hashingIsStableAcrossJsonOrderingAndBindsNestedCard() {
        val first = JSONObject().put("z", 1).put("card", JSONObject().put("b", 2).put("a", "x"))
        val second = JSONObject().put("card", JSONObject().put("a", "x").put("b", 2)).put("z", 1)
        assertEquals(PhonePairingDeliveryLedger.payloadHash(first), PhonePairingDeliveryLedger.payloadHash(second))
        second.getJSONObject("card").put("a", "changed")
        assertNotEquals(PhonePairingDeliveryLedger.payloadHash(first), PhonePairingDeliveryLedger.payloadHash(second))
    }

    @Test fun invalidOrReceiptControlsCannotEnterReliableQueue() {
        val rig = Rig()
        assertFalse(rig.enqueue(rig.ledger(), rig.payload(type = PhoneContactCard.RECEIPT_TYPE)))
        assertFalse(rig.enqueue(rig.ledger(), rig.payload().put("control_id", "invalid")))
        assertFalse(rig.enqueue(rig.ledger(), rig.payload().put("time", 0)))
        assertNull(rig.ledger().nextDelay())
    }
}
