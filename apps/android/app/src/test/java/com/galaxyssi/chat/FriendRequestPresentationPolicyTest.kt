package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendRequestPresentationPolicyTest {
    @Test
    fun outgoingPendingRequestRemainsVisibleWhileWaiting() {
        val request = request("outgoing", "pending")

        assertTrue(FriendRequestPresentationPolicy.isVisible(request, contactIsVerified = false))
        assertFalse(FriendRequestPresentationPolicy.isAdded(request, contactIsVerified = false))
    }

    @Test
    fun outgoingApprovedRequestRemainsVisibleAsAdded() {
        val request = request("outgoing", "approved")

        assertTrue(FriendRequestPresentationPolicy.isVisible(request, contactIsVerified = true))
        assertTrue(FriendRequestPresentationPolicy.isAdded(request, contactIsVerified = true))
    }

    @Test
    fun verifiedContactRepairsStaleOutgoingPendingPresentation() {
        val request = request("outgoing", "pending")

        assertTrue(FriendRequestPresentationPolicy.isAdded(request, contactIsVerified = true))
    }

    @Test
    fun completedIncomingRequestLivesOnlyInContacts() {
        val request = request("incoming", "approved")

        assertFalse(FriendRequestPresentationPolicy.isVisible(request, contactIsVerified = true))
    }

    private fun request(direction: String, status: String): JSONObject = JSONObject()
        .put("direction", direction)
        .put("status", status)
}
