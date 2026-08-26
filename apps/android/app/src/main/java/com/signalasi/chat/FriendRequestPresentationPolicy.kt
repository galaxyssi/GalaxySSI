package com.signalasi.chat

import org.json.JSONObject

internal object FriendRequestPresentationPolicy {
    fun isAdded(request: JSONObject, contactIsVerified: Boolean): Boolean =
        request.optString("status") == "approved" || contactIsVerified

    fun isVisible(request: JSONObject, contactIsVerified: Boolean): Boolean {
        if (request.optString("status") == "pending") return true
        return request.optString("direction") == "outgoing" &&
            isAdded(request, contactIsVerified)
    }
}
