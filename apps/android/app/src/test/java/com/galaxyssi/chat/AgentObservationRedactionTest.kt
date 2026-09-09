package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentObservationRedactionTest {
    @Test fun authorizationHeadersAndSessionTokensAreMaskedInCommandOutput() {
        val output = AgentObservationRedaction.redact(
            "Authorization: Basic dXNlcjpzZWNyZXQ=\nAuthorization: Bearer ABCDEFGHIJK\nsession_token=SESSION_SECRET\nexit_code=1")
        assertFalse(output.contains("dXNlcjpzZWNyZXQ="))
        assertFalse(output.contains("ABCDEFGHIJK"))
        assertFalse(output.contains("SESSION_SECRET"))
        assertTrue(output.contains("exit_code=1"))
    }

    @Test fun nestedJsonCredentialsAndArraysAreRedactedStructurally() {
        val input = """{"api_key":"top secret","values":[{"Authorization":"Bearer TOP_SECRET"}],"count":12345678}"""
        val output = AgentObservationRedaction.redact(input)
        val json = JSONObject(output)
        assertEquals("[redacted]", json.getString("api_key"))
        assertEquals("[redacted]", json.getJSONArray("values").getJSONObject(0).getString("Authorization"))
        assertEquals(12345678, json.getInt("count"))
        assertFalse(output.contains("top secret"))
        assertFalse(output.contains("TOP_SECRET"))
    }

    @Test fun quotedAndPartialCommandAssignmentsAreRedacted() {
        val output = AgentPlannerObservation.sanitize(
            "Command failed password='a b c' api_key=TOP_SECRET auth_token=ANOTHER_SECRET exit_code=1", 1000)!!
        assertFalse(output.contains("a b c"))
        assertFalse(output.contains("TOP_SECRET"))
        assertFalse(output.contains("ANOTHER_SECRET"))
        assertTrue(output.contains("exit_code=1"))
    }

    @Test fun partialJsonDoesNotLeakAQuotedSecret() {
        val output = AgentPlannerObservation.sanitize("""{"api_key":"TOP_SECRET", "error":"timeout""", 1000)!!
        assertFalse(output.contains("TOP_SECRET"))
        assertTrue(output.contains("timeout"))
    }

    @Test fun privateKeyIsRemovedBeforeTailCompaction() {
        val input = "started -----BEGIN RSA PRIVATE KEY-----\nTOP_SECRET\n-----END RSA PRIVATE KEY----- failed"
        val output = AgentPlannerObservation.sanitize(input, 1000)!!
        assertFalse(output.contains("TOP_SECRET"))
        assertTrue(output.contains("failed"))
    }

    @Test fun jsonFollowedByTextDoesNotDiscardTheFailureTail() {
        val output = AgentPlannerObservation.sanitize("""{"api_key":"TOP_SECRET"} terminal_error=missing_git""", 1000)!!
        assertFalse(output.contains("TOP_SECRET"))
        assertTrue(output.contains("terminal_error=missing_git"))
    }
}
