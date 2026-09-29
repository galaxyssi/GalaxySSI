package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessPhaseTimingDeviceTest {
    private fun assessment() = JSONObject().put("artifact_presence_wait_ms", 40L)
        .put("save_verification_ms", 20L).put("all_artifacts_present", true)
        .put("all_artifacts_verified", true).put("correct", true)

    @Test fun separatesWaitAuditSaveAndUiWithoutChangingReplyTiming() {
        val result = businessPhaseTiming(100, 110, 200, 230, true, assessment())
        assertEquals(100L, result.getLong("reply_terminal_ms"))
        assertEquals(150L, result.getLong("artifacts_present_ms"))
        assertEquals(50L, result.getLong("artifact_audit_ms"))
        assertEquals(20L, result.getLong("save_verification_ms"))
        assertEquals(200L, result.getLong("artifacts_verified_ms"))
        assertEquals(30L, result.getLong("ui_check_ms"))
        assertEquals(230L, result.getLong("observed_end_to_end_ms"))
    }

    @Test fun missingOrFailedArtifactIsNotReportedAsReadyAtZero() {
        val missing = assessment().put("all_artifacts_present", false).put("correct", false)
        val result = businessPhaseTiming(100, 110, 200, 230, true, missing)
        assertTrue(result.isNull("artifacts_present_ms"))
        assertTrue(result.isNull("artifacts_verified_ms"))
        val text = businessPhaseTiming(100, 110, 200, 230, false, JSONObject())
        assertTrue(text.isNull("artifact_presence_wait_ms"))
        assertTrue(text.isNull("artifact_audit_ms"))
    }

    @Test fun rejectsImpossibleChronology() {
        assertThrows(IllegalArgumentException::class.java) { businessPhaseTiming(100, 90, 200, 230, true, assessment()) }
        assertThrows(IllegalArgumentException::class.java) { businessPhaseTiming(100, 110, 120, 230, true, assessment()) }
    }
}
