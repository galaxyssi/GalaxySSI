package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DesktopRemoteControlAuthorizationTest {
    @Test
    fun parsesTraceableAuthorizedAppRecord() {
        val authorization = parseDesktopControlAuthorization(JSONObject()
            .put("authorization_id", "dca_test")
            .put("app_instance_id", "phone_route_01")
            .put("app_name", "GalaxySSI")
            .put("app_platform", "android")
            .put("phone_name", "Galaxy")
            .put("app_identity_fingerprint", "AA:BB:CC")
            .put("grant_source", "pairing_qr")
            .put("access_profile", "full_desktop_executor")
            .put("access_scopes", JSONArray()
                .put("desktop.execute")
                .put("desktop.observe"))
            .put("granted_at", 1_000L)
            .put("last_used_at", 2_000L)
            .put("status", "active")
            .put("allowed_tools", JSONArray()
                .put("desktop.screenshot")
                .put("desktop.click"))
            .put("desktop_session_id", "session_01")
            .put("desktop_session_expires_at", 3_000L)
        )

        requireNotNull(authorization)
        assertEquals("dca_test", authorization.authorizationId)
        assertEquals("phone_route_01", authorization.appInstanceId)
        assertEquals("GalaxySSI", authorization.appName)
        assertEquals("android", authorization.appPlatform)
        assertEquals("AA:BB:CC", authorization.phoneFingerprint)
        assertEquals("pairing_qr", authorization.grantSource)
        assertEquals("full_desktop_executor", authorization.accessProfile)
        assertEquals(
            listOf("desktop.execute", "desktop.observe"),
            authorization.accessScopes
        )
        assertEquals(
            listOf("desktop.screenshot", "desktop.click"),
            authorization.allowedTools
        )
        assertEquals("active", authorization.status)
    }

    @Test
    fun keepsRevokedRecordWithoutAnActiveSession() {
        val authorization = parseDesktopControlAuthorization(JSONObject()
            .put("authorization_id", "dca_revoked")
            .put("app_instance_id", "phone_route_02")
            .put("app_name", "GalaxySSI")
            .put("app_platform", "android")
            .put("status", "revoked")
            .put("revoked_at", 4_000L)
            .put("revoke_reason", "revoked_by_phone")
        )

        requireNotNull(authorization)
        assertEquals("revoked", authorization.status)
        assertEquals(4_000L, authorization.revokedAt)
        assertEquals("revoked_by_phone", authorization.revokeReason)
        assertEquals("", authorization.desktopSessionId)
        assertEquals(0L, authorization.desktopSessionExpiresAt)
    }

    @Test
    fun rejectsMalformedNonPendingRecord() {
        assertNull(parseDesktopControlAuthorization(JSONObject().put("status", "active")))
    }
}
