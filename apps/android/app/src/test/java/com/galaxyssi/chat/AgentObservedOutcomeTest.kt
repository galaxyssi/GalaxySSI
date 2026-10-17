package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentObservedOutcomeTest {
    private fun outcome(tool: String = "galaxyssi.delivery.status", path: String = "/delivery_status", value: Any = "RX_STORED") =
        AgentObservedOutcome("delivery", tool, mapOf("/message_id" to "message-1", "/recipient_id" to "peer-1"), mapOf(path to value))
    private fun receipt(tool: String, output: String) = AgentAction("fixture", AgentActionKind.CALL_NATIVE_TOOL,
        tool, AgentRisk.LOW, AgentActionStatus.COMPLETED, "fixture", mapOf("tool_id" to tool), evidence = output)
    private val ack = """{"message_id":"message-1","recipient_id":"peer-1","delivery_status":"RX_STORED"}"""

    @Test fun recipientAcknowledgementNotQueueSuccessProvesDelivery() {
        val required = outcome()
        assertTrue(AgentObservedOutcomeEvidence.missing(listOf(required), listOf(receipt(required.toolId, ack))).isEmpty())
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(required), listOf(receipt(required.toolId,
            """{"message_id":"message-1","recipient_id":"peer-1","delivery_status":"QUEUED","success":true}"""))).isEmpty())
    }
    @Test fun evidenceMustMatchBothMessageAndRecipient() {
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(outcome()),
            listOf(receipt(outcome().toolId, ack.replace("peer-1", "peer-2")))).isEmpty())
    }
    @Test fun latestObservationOverridesOlderSuccess() {
        val history = listOf(receipt(outcome().toolId, ack), receipt(outcome().toolId, ack.replace("RX_STORED", "UNKNOWN")))
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(outcome()), history).isEmpty())
    }
    @Test fun observationBeforeLatestMutationIsStale() {
        val history = listOf(receipt(outcome().toolId, ack), receipt("galaxyssi.message.send", "{}"))
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(outcome().copy(afterToolId = "galaxyssi.message.send")), history).isEmpty())
    }
    @Test fun bareAcceptanceAndModelProseAreNotPostconditions() {
        for (path in listOf("/success", "/accepted", "/text", "/message", "/exit_code", "/ui_changed"))
            assertNull(AgentObservedOutcome.parse(outcome(path = path, value = true).toJson()))
    }
    @Test fun fileOpeningCanBeCheckedIndependentlyOfExistence() {
        val file = AgentObservedOutcome("file", "galaxyssi.file.inspect", mapOf("/path" to "outputs/report.pdf"),
            mapOf("/exists" to true, "/readable" to true, "/format_valid" to true))
        val corrupt = receipt(file.toolId, """{"path":"outputs/report.pdf","exists":true,"readable":true,"format_valid":false}""")
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(file), listOf(corrupt)).isEmpty())
        assertTrue(AgentObservedOutcomeEvidence.missing(listOf(file), listOf(corrupt.copy(evidence = corrupt.evidence.replace("false", "true")))).isEmpty())
    }
    @Test fun requirementsPersistAndCannotSilentlyLoseChecks() {
        val requirement = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = listOf(outcome()))
        assertEquals(requirement, AgentCompletionRequirements.parse(JSONObject(requirement.toJson().toString())))
        assertFalse(requirement.copy(outcomes = emptyList(), reason = "tool returned success").canReplace(requirement))
    }
    @Test fun unverifiedReceiptConstrainsFinalAnswer() {
        val action = receipt("galaxyssi.agent_action.set.alarm", """{"message":"Not verified","metadata":{"goal_status":"dispatched"}}""")
        assertEquals("Not verified", AgentGoalEvidence.unverifiedOutcome(listOf(action)))
        assertFalse(AgentGoalEvidence.hasVerifiedOutcome(listOf(action)))
    }
    @Test fun incorrectObservationFieldsCanBeRevisedWithReasonWithoutDroppingGoal() {
        val original = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = listOf(outcome()))
        val corrected = original.copy(outcomes = listOf(outcome(path = "/actual_delivery_state")))
        assertFalse(corrected.canReplace(original))
        assertTrue(corrected.copy(reason = "The tool schema exposes actual_delivery_state, not delivery_status").canReplace(original))
    }
    @Test fun olderVerifiedOutcomeCannotHideNewerUncertainty() {
        val success = receipt("galaxyssi.agent_action.set.alarm", """{"metadata":{"goal_status":"verified"}}""")
        val latest = success.copy(status = AgentActionStatus.FAILED, evidence = """{"metadata":{"goal_status":"unknown"}}""")
        assertFalse(AgentGoalEvidence.hasVerifiedOutcome(listOf(success, latest)))
    }

    @Test fun notificationHandoffCaveatSurvivesPlannerAndUiEvidence() {
        val output = AgentGoalEvidence.withDeliveryEvidence(mapOf("dispatch_accepted" to true,
            "delivery_verified" to false, "notification_key_sha256" to "fixture"),
            mapOf("handoff_only" to true, "delivery_receipt_available" to false), zh = true)
        assertEquals("false", AgentGoalEvidence.metadata(output)["business_success_verified"])
        assertEquals("dispatched", AgentGoalEvidence.metadata(output)["goal_status"])
        assertEquals("fixture", output["notification_key_sha256"])
        val action = receipt("galaxyssi.notification.reply", AgentNativeJsonCodec.stringify(output))
        assertEquals("已提交发送请求，尚未确认对方收到。", AgentGoalEvidence.unverifiedOutcome(listOf(action)))
        assertFalse(AgentGoalEvidence.hasVerifiedOutcome(listOf(action)))
    }

    @Test fun missingDeliveryReceiptOverridesContradictorySuccess() {
        val output = AgentGoalEvidence.withDeliveryEvidence(mapOf("delivery_verified" to false,
            "metadata" to mapOf("goal_status" to "verified")), emptyMap(), zh = false)
        assertEquals("unknown", AgentGoalEvidence.metadata(output)["goal_status"])
        assertEquals("false", AgentGoalEvidence.metadata(output)["business_success_verified"])
    }

    @Test fun normalToolEvidenceAndActualReceiptsAreNotRewritten() {
        val output = mapOf("delivery_verified" to true, "receipt_id" to "ack-1")
        assertSame(output, AgentGoalEvidence.withDeliveryEvidence(output, emptyMap(), zh = false))
        assertTrue(AgentGoalEvidence.metadata(output).isEmpty())
    }

    @Test fun missingMessageCannotTurnUnverifiedStateIntoSuccess() {
        val action = receipt("galaxyssi.agent_action.set.alarm", """{"metadata":{"goal_status":"unknown"}}""")
        assertNotNull(AgentGoalEvidence.unverifiedOutcome(listOf(action)))
        assertNotNull(AgentGoalEvidence.unverifiedOutcome(listOf(action.copy(status = AgentActionStatus.FAILED,
            evidence = """{"metadata":{"goal_status":"verified"}}"""))))
    }

    @Test fun restoredReceiptsCannotTurnDispatchIntoVerifiedOutcome() {
        val accepted = AgentActionResult("fixture", true, "Submitted")
        assertFalse(AgentGoalEvidence.permitsSuccess(null))
        assertFalse(AgentGoalEvidence.permitsSuccess(accepted.copy(success = false)))
        for (metadata in listOf(mapOf("business_success_verified" to "false"),
            mapOf("goal_status" to "unknown"), mapOf("goal_status" to "dispatched"),
            mapOf("native_tool_output" to """{"dispatch_accepted":true,"delivery_verified":false}"""),
            mapOf("native_tool_output" to """{"metadata":{"business_success_verified":"false"}}"""))) {
            assertFalse(metadata.toString(), AgentGoalEvidence.permitsSuccess(accepted.copy(metadata = metadata)))
        }
        assertTrue(AgentGoalEvidence.permitsSuccess(accepted.copy(metadata =
            mapOf("goal_status" to "verified", "business_success_verified" to "true"))))
    }

    @Test fun unknownOutcomeContinuesInspectionButMissingCapabilityIsExplicit() {
        val recoverable = receipt("galaxyssi.agent_action.set.alarm", """{"message":"Not verified","metadata":{"goal_status":"unknown","next_action":"inspect_phone_ui_before_recovery"}}""")
        assertTrue(requireNotNull(AgentGoalEvidence.pendingReceipt(listOf(recoverable))).canInspect)
        val blocked = receipt("galaxyssi.agent_action.set.alarm", """{"message":"Enable access","metadata":{"goal_status":"blocked","required_capability":"accessibility"}}""")
        assertFalse(requireNotNull(AgentGoalEvidence.pendingReceipt(listOf(blocked))).canInspect)
        val output = AgentGoalEvidence.withDeliveryEvidence(mapOf("dispatch_accepted" to true, "delivery_verified" to false),
            mapOf("delivery_receipt_available" to false), zh = false)
        assertEquals("recipient_delivery_receipt", AgentGoalEvidence.metadata(output)["required_capability"])
    }

    @Test fun directNotificationReplyUsesSameUnverifiedReceiptAsNativeTool() {
        val action = receipt("fixture", "{}").copy(kind = AgentActionKind.REPLY_NOTIFICATION,
            parameters = mapOf("notification_key" to "fixture-key", "reply_text" to "private reply"))
        val accepted = AgentGoalEvidence.notificationReply(action,
            AgentNotificationReplyResult(true, "Sent", notificationPackage = "fixture.package"), zh = false)
        assertTrue(accepted.success)
        assertFalse(AgentGoalEvidence.permitsSuccess(accepted))
        assertEquals("dispatched", accepted.metadata["goal_status"])
        assertEquals("recipient_delivery_receipt", accepted.metadata["required_capability"])
        assertEquals("fixture.package", accepted.metadata["notification_package"])
        assertEquals(AgentNativeJsonCodec.sha256("fixture-key"), accepted.metadata["notification_key_sha256"])
        assertFalse(accepted.toString().contains("private reply"))
        val failed = AgentGoalEvidence.notificationReply(action,
            AgentNotificationReplyResult(false, "Target expired", code = "notification_not_found"), zh = true)
        assertFalse(failed.success)
        assertEquals("failed", failed.metadata["goal_status"])
        assertEquals("Target expired", failed.message)
        assertEquals("notification_not_found", failed.metadata["error_code"])
    }
}
