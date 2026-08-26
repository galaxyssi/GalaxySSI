package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneRelationshipRouteRefreshTest {
    private val remoteId = "signalasi:${"a".repeat(16)}"
    private val remoteFingerprint = "a".repeat(64)
    private val localFingerprint = "b".repeat(64)
    private val routeId = "c".repeat(22)
    private val linkSecret = "d".repeat(43)

    @Test
    fun trustedMatchingIdentityRotatesRouteWithoutDroppingContactState() {
        val existing = JSONObject()
            .put("id", remoteId)
            .put("signalasi_id", remoteId)
            .put("name", "Renamed friend")
            .put("user_renamed", true)
            .put("trust_state", "verified")
            .put("identity_fingerprint", remoteFingerprint)
            .put("client_route_id", "e".repeat(22))
            .put("link_secret", "f".repeat(43))
            .put("local_identity_fingerprint", localFingerprint)
        val card = remoteCard()

        val refreshed = PhoneRelationshipRouteRefresh.apply(
            existing,
            card,
            linkSecret,
            routeId,
            localFingerprint,
            nowMillis = 42L
        )!!

        assertEquals("Renamed friend", refreshed.getString("name"))
        assertTrue(refreshed.getBoolean("user_renamed"))
        assertEquals(routeId, refreshed.getString("client_route_id"))
        assertEquals(linkSecret, refreshed.getString("link_secret"))
        assertEquals(42L, refreshed.getLong("relationship_rotated_at"))
    }

    @Test
    fun differentOrUntrustedIdentityCannotRotateRelationship() {
        val existing = JSONObject()
            .put("id", remoteId)
            .put("signalasi_id", remoteId)
            .put("trust_state", "verified")
            .put("identity_fingerprint", remoteFingerprint)

        assertNull(
            PhoneRelationshipRouteRefresh.apply(
                existing,
                remoteCard().put("identity_fingerprint", "9".repeat(64)),
                linkSecret,
                routeId,
                localFingerprint
            )
        )
        assertNull(
            PhoneRelationshipRouteRefresh.apply(
                JSONObject(existing.toString()).put("trust_state", "unverified"),
                remoteCard(),
                linkSecret,
                routeId,
                localFingerprint
            )
        )
    }

    private fun remoteCard(): JSONObject = JSONObject()
        .put("signalasi_id", remoteId)
        .put("identity_fingerprint", remoteFingerprint)
        .put("identity_public_key", "public-key")
}
