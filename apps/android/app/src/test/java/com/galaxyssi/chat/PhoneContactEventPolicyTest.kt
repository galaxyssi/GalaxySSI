package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PhoneContactEventPolicyTest {
    private fun request(status: String, direction: String = "outgoing") =
        JSONObject().put("status", status).put("direction", direction)

    @Test fun firstOutgoingApprovalNotifiesOnce() {
        assertEquals("phone_contact_request_approved", PhoneContactEventPolicy.eventType(
            PhoneContactCard.APPROVAL_TYPE, request("pending"), request("approved"), false))
    }

    @Test fun renewedApprovalIdsAndRestartedReceiverRemainSilent() {
        repeat(100) {
            val restored = JSONObject(request("approved").toString())
            assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
                PhoneContactCard.APPROVAL_TYPE, restored, request("approved"), true))
        }
    }

    @Test fun approvedRelationshipDoesNotNeedASignalSessionOrRequestHistoryToSuppressAlerts() {
        for (previous in listOf(null, request("pending"), request("approved"))) {
            assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
                PhoneContactCard.APPROVAL_TYPE, previous, request("approved"), true))
        }
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.APPROVAL_TYPE, request("approved"), request("approved"), false))
    }

    @Test fun deletedRelationshipCanNotifyAfterANewOutgoingRequestIsApproved() {
        assertEquals("phone_contact_request_approved", PhoneContactEventPolicy.eventType(
            PhoneContactCard.APPROVAL_TYPE, request("pending"), request("approved"), false))
        for (status in listOf("deleted", "rejected")) {
            assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
                PhoneContactCard.APPROVAL_TYPE, request(status), request(status), false))
        }
    }

    @Test fun incomingRequestNotifiesOnlyWhenItBecomesPending() {
        for (previous in listOf(null, request("deleted", "incoming"), request("rejected", "incoming"))) {
            assertEquals("phone_contact_request_received", PhoneContactEventPolicy.eventType(
                PhoneContactCard.REQUEST_TYPE, previous, request("pending", "incoming"), false))
        }
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.REQUEST_TYPE, request("pending", "incoming"), request("pending", "incoming"), false))
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.REQUEST_TYPE, request("approved"), request("approved"), true))
    }

    @Test fun IncomingRequestCannotProduceAnOutgoingApprovalAlert() {
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.APPROVAL_TYPE, request("pending", "incoming"), request("pending", "incoming"), false))
    }

    @Test fun rejectionAndSessionRefreshKeepTheirDistinctEvents() {
        assertEquals("phone_contact_request_rejected", PhoneContactEventPolicy.eventType(
            PhoneContactCard.REJECTION_TYPE, request("pending"), request("rejected"), false))
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.REJECTION_TYPE, request("rejected"), request("rejected"), false))
        assertEquals("phone_contact_session_refreshed", PhoneContactEventPolicy.eventType(
            PhoneContactCard.BUNDLE_REFRESH_TYPE, request("approved"), request("approved"), true))
        assertEquals("phone_contact_session_ready", PhoneContactEventPolicy.eventType(
            PhoneContactCard.BUNDLE_RESPONSE_TYPE, request("approved"), request("approved"), true))
    }
}
