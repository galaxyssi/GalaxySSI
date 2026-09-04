package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendRequestUnreadPolicyTest {
    @Test
    fun onlyUnreadIncomingPendingRequestsAreCounted() {
        val requests = JSONArray()
            .put(request("incoming-new", "incoming", "pending", false))
            .put(request("incoming-read", "incoming", "pending", true))
            .put(request("outgoing", "outgoing", "pending", false))
            .put(request("approved", "incoming", "approved", false))

        assertEquals(1, FriendRequestUnreadPolicy.unreadCount(requests))
    }

    @Test
    fun openingNewFriendsMarksIncomingRequestsRead() {
        val requests = JSONArray()
            .put(request("first", "incoming", "pending", false))
            .put(request("second", "incoming", "pending", false))
            .put(request("outgoing", "outgoing", "pending", false))

        assertEquals(2, FriendRequestUnreadPolicy.markIncomingPendingRead(requests))
        assertEquals(0, FriendRequestUnreadPolicy.unreadCount(requests))
        assertFalse(requests.getJSONObject(2).optBoolean("is_read"))
    }

    @Test
    fun duplicatePendingRequestKeepsItsReadStateButNewRequestStartsUnread() {
        val viewed = request("existing", "incoming", "pending", true)

        assertTrue(FriendRequestUnreadPolicy.isReadForPendingRequest(viewed, "incoming"))
        assertFalse(FriendRequestUnreadPolicy.isReadForPendingRequest(null, "incoming"))
        assertTrue(FriendRequestUnreadPolicy.isReadForPendingRequest(null, "outgoing"))
    }

    private fun request(id: String, direction: String, status: String, read: Boolean) = JSONObject()
        .put("id", id)
        .put("direction", direction)
        .put("status", status)
        .put("is_read", read)
}
