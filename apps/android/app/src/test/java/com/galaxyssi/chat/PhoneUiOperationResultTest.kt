package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class PhoneUiOperationResultTest {
    @Test fun acceptedControlIsNotBusinessSuccess() {
        val result = PhoneUiOperationResult.from(mapOf("accepted" to true, "revision" to "r1"), "rejected", "Not accepted")
        assertTrue(result.isSuccess)
        assertEquals(false, result.output["business_success_verified"])
        assertEquals("r1", result.output["revision"])
    }

    @Test fun rejectedControlPreservesTheActualDiagnostic() {
        val result = PhoneUiOperationResult.from(mapOf("accepted" to false, "reason" to "node_disabled"), "rejected", "Not accepted")
        assertFalse(result.isSuccess)
        assertEquals("node_disabled", result.error!!.details["reason"])
        assertEquals(true, result.error!!.details["observation_required"])
        assertEquals(false, result.error!!.details["goal_terminal"])
    }

    @Test fun stalePageNeverClaimsTheActionExecuted() {
        val result = PhoneUiOperationResult.stale(5, "fresh-revision")
        assertEquals("ui_observation_stale", result.error!!.code)
        assertEquals(false, result.error!!.details["executed"])
        assertEquals(5, result.error!!.details["current_window_id"])
        assertEquals("fresh-revision", result.error!!.details["current_revision"])
    }
}
