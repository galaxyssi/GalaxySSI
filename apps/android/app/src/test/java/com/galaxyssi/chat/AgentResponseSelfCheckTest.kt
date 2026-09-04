package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentResponseSelfCheckTest {
    @Test
    fun substantiveResponsePasses() {
        val result = AgentResponseSelfCheck.evaluate(
            "Summarize the report",
            "The report identifies three launch risks and recommends a one-day delay."
        )

        assertTrue(result.accepted)
        assertEquals(AgentResponseSelfCheckStatus.PASSED, result.status)
    }

    @Test
    fun acknowledgementOnlyResponseRequestsRepair() {
        val result = AgentResponseSelfCheck.evaluate(
            "Build and verify the Android app",
            "Got it. I will handle this now."
        )

        assertFalse(result.accepted)
        assertEquals(listOf("acknowledgement_only"), result.reasons)
    }

    @Test
    fun providedAttachmentCannotBeReportedAsMissing() {
        val result = AgentResponseSelfCheck.evaluate(
            "Review this worksheet",
            "I cannot see any attachment. Please upload the file.",
            hasAttachments = true
        )

        assertEquals(AgentResponseSelfCheckStatus.REPAIR, result.status)
        assertTrue("available_attachment_ignored" in result.reasons)
    }

    @Test
    fun verifiedArtifactAllowsShortCompletionMessage() {
        val result = AgentResponseSelfCheck.evaluate(
            "Create a ZIP archive",
            "Done.",
            hasOutputArtifacts = true
        )

        assertTrue(result.accepted)
    }

    @Test
    fun richArtifactCanBeTheEntireResponse() {
        val result = AgentResponseSelfCheck.evaluate(
            "Create and return the annotated image",
            "",
            hasOutputArtifacts = true
        )

        assertTrue(result.accepted)
    }

    @Test
    fun chineseAcknowledgementOnlyResponseRequestsRepair() {
        val result = AgentResponseSelfCheck.evaluate(
            "\u5206\u6790\u8fd9\u4efd\u62a5\u544a",
            "\u6536\u5230\uff0c\u6211\u4f1a\u9a6c\u4e0a\u5904\u7406\u3002"
        )

        assertFalse(result.accepted)
        assertEquals(listOf("acknowledgement_only"), result.reasons)
    }

    @Test
    fun greetingCannotReceiveFutureOnlyAcknowledgement() {
        val result = AgentResponseSelfCheck.evaluate(
            "hello",
            "Got it. I will handle this now."
        )

        assertFalse(result.accepted)
        assertEquals(listOf("acknowledgement_only"), result.reasons)
    }

    @Test
    fun userAcknowledgementCanReceiveShortAcknowledgement() {
        val result = AgentResponseSelfCheck.evaluate("thank you", "Okay")

        assertTrue(result.accepted)
    }

    @Test
    fun explicitEnglishShortReplyRequestAcceptsAcknowledgement() {
        val result = AgentResponseSelfCheck.evaluate(
            "DeepSeek reply only OK for this latency test",
            "OK"
        )

        assertTrue(result.accepted)
        assertEquals(AgentResponseSelfCheckStatus.PASSED, result.status)
    }

    @Test
    fun explicitChineseShortReplyRequestAcceptsAcknowledgement() {
        val result = AgentResponseSelfCheck.evaluate(
            "\u53ea\u56de\u590d\u6536\u5230\uff0c\u4e0d\u8981\u5176\u4ed6\u5185\u5bb9",
            "\u6536\u5230"
        )

        assertTrue(result.accepted)
        assertEquals(AgentResponseSelfCheckStatus.PASSED, result.status)
    }

    @Test
    fun unrelatedShortAcknowledgementStillRequestsRepair() {
        val result = AgentResponseSelfCheck.evaluate(
            "Explain why the request failed",
            "OK"
        )

        assertFalse(result.accepted)
        assertEquals(listOf("acknowledgement_only"), result.reasons)
    }

    @Test
    fun responseIdentityMustMatchBoundTurn() {
        val result = AgentResponseSelfCheck.evaluate(
            "Explain the error",
            "The token expired.",
            expectedIdentity = mapOf("task_id" to "task-1", "turn_id" to "turn-2"),
            responseIdentity = mapOf("task_id" to "task-1", "turn_id" to "turn-1")
        )

        assertEquals(AgentResponseSelfCheckStatus.REJECTED, result.status)
        assertEquals(listOf("identity_mismatch"), result.reasons)
    }
}
