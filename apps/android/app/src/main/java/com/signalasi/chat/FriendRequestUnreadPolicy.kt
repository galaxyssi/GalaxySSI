package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

internal object FriendRequestUnreadPolicy {
    fun isReadForPendingRequest(previous: JSONObject?, direction: String): Boolean {
        if (direction == "outgoing") return true
        if (previous == null || previous.optString("status") != "pending") return false
        return previous.optBoolean("is_read", false)
    }

    fun unreadCount(requests: JSONArray): Int = (0 until requests.length()).count { index ->
        val request = requests.optJSONObject(index) ?: return@count false
        request.optString("status") == "pending" &&
            request.optString("direction") != "outgoing" &&
            !request.optBoolean("is_read", false)
    }

    fun markIncomingPendingRead(requests: JSONArray): Int {
        var changed = 0
        for (index in 0 until requests.length()) {
            val request = requests.optJSONObject(index) ?: continue
            if (request.optString("status") != "pending" ||
                request.optString("direction") == "outgoing" ||
                request.optBoolean("is_read", false)
            ) continue
            request.put("is_read", true)
            changed += 1
        }
        return changed
    }
}
