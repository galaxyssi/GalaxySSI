package com.galaxyssi.chat

import org.json.JSONObject

internal object PhoneContactEventPolicy {
    fun eventType(
        controlType: String,
        previous: JSONObject?,
        current: JSONObject?,
        previouslyVerified: Boolean
    ): String = when (controlType) {
        PhoneContactCard.REQUEST_TYPE -> if (
            !previouslyVerified && current?.optString("status") == "pending" &&
            current.optString("direction") == "incoming" &&
            !(previous?.optString("status") == "pending" && previous.optString("direction") == "incoming")
        ) "phone_contact_request_received" else "phone_contact_session_ready"
        PhoneContactCard.APPROVAL_TYPE -> if (
            !previouslyVerified && previous?.optString("status") == "pending" &&
            previous.optString("direction") == "outgoing" && current?.optString("status") == "approved"
        ) "phone_contact_request_approved" else "phone_contact_session_ready"
        PhoneContactCard.REJECTION_TYPE -> if (
            !previouslyVerified && previous?.optString("status") == "pending" &&
            previous.optString("direction") == "outgoing" && current?.optString("status") == "rejected"
        ) "phone_contact_request_rejected" else "phone_contact_session_ready"
        PhoneContactCard.BUNDLE_REFRESH_TYPE -> "phone_contact_session_refreshed"
        else -> "phone_contact_session_ready"
    }
}
