package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentDeviceStateEvidenceTest {
    private val volumeTool = AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET
    private val observed = mapOf("stream" to "music", "requested_percent" to 50, "target_volume" to 8,
        "volume" to 8, "max" to 15, "min" to 0, "state_verified" to true, "observed_at_epoch_millis" to 1000L)

    @Test fun verifiedStateControlsBothReplyAndCompletionMetadata() {
        val output = AgentDeviceStateEvidence.normalize(volumeTool, observed, zh = false)
        assertEquals("music volume is now 53%.", output["message"])
        assertEquals("verified", AgentGoalEvidence.metadata(output)["goal_status"])
        assertTrue(AgentGoalEvidence.permitsSuccess(result(volumeTool, output)))
        assertTrue(AgentGoalEvidence.hasVerifiedOutcome(listOf(action(volumeTool, output))))
    }

    @Test fun contradictoryAndMissingReadbacksCannotBecomeSuccess() {
        for (raw in listOf(observed + ("volume" to 3), observed - "volume", observed - "observed_at_epoch_millis",
            observed + ("state_verified" to false), observed + ("stream" to "missing"))) {
            val output = AgentDeviceStateEvidence.normalize(volumeTool,
                raw + mapOf("request_accepted" to true, "metadata" to mapOf("goal_status" to "verified")), zh = false)
            assertEquals(false, output["state_verified"])
            assertFalse(AgentGoalEvidence.permitsSuccess(result(volumeTool, output)))
            assertTrue(output["message"].toString().contains("not confirmed"))
            assertTrue(requireNotNull(AgentGoalEvidence.pendingReceipt(listOf(action(volumeTool, output)))).canInspect)
        }
    }

    @Test fun requestedFlashlightStateDoesNotBecomeObservedState() {
        val tool = AgentHardwareNativeTools.FLASHLIGHT_SET
        val raw = mapOf("requested_enabled" to true, "request_accepted" to true, "state_verified" to false)
        for (zh in listOf(false, true)) {
            val output = AgentDeviceStateEvidence.normalize(tool, raw, zh)
            assertEquals("false", AgentGoalEvidence.metadata(output)["business_success_verified"])
            assertFalse(AgentGoalEvidence.permitsSuccess(result(tool, output)))
            val pending = requireNotNull(AgentGoalEvidence.pendingReceipt(listOf(action(tool, output))))
            assertFalse(pending.canInspect)
            assertEquals("torch_state_observation", pending.requiredCapability)
            assertFalse(output["message"].toString().contains("turned on"))
            assertFalse(output["message"].toString().contains("\u5df2\u6253\u5f00"))
        }
    }

    @Test fun restoredLegacyStateCannotBypassVerification() {
        val tool = AgentHardwareNativeTools.FLASHLIGHT_SET
        val raw = mapOf("requested_enabled" to true, "state_verified" to false,
            "metadata" to mapOf("goal_status" to "verified"))
        assertFalse(AgentGoalEvidence.permitsSuccess(result(tool, raw)))
        assertFalse(AgentGoalEvidence.hasVerifiedOutcome(listOf(action(tool, raw))))
        assertNotNull(AgentGoalEvidence.pendingReceipt(listOf(action(tool, raw))))
        assertFalse(AgentGoalEvidence.permitsSuccess(result(volumeTool, mapOf("volume" to 8, "max" to 15))))
    }

    @Test fun muteMismatchCannotBeRenderedAsRequestedSuccess() {
        val tool = AgentAndroidSystemNativeTools.AUDIO_MUTE_SET
        val raw = mapOf("stream" to "music", "requested_muted" to true, "muted" to false,
            "observed_at_epoch_millis" to 1000L, "state_verified" to true)
        assertFalse(AgentDeviceStateEvidence.verified(tool, raw))
        val observedMute = raw + ("muted" to true)
        assertTrue(AgentDeviceStateEvidence.verified(tool, observedMute))
        assertEquals("music is muted.", AgentDeviceStateEvidence.normalize(tool, observedMute, false)["message"])
    }

    @Test fun requestedFieldsCannotServeAsObservedPostconditions() {
        for (field in listOf("requested_enabled", "requested_percent", "target_volume", "requested_muted",
            "request_accepted", "dispatch_attempted")) {
            val requirement = AgentObservedOutcome("audio", volumeTool, mapOf("/stream" to "music"), mapOf("/$field" to true))
            assertNull(field, AgentObservedOutcome.parse(requirement.toJson()))
        }
    }

    @Test fun actualReadbackIsBoundToTheCorrectStreamAndLatestMutation() {
        val requirement = AgentObservedOutcome("volume", volumeTool, mapOf("/stream" to "music"),
            mapOf("/state_verified" to true, "/volume" to 8), volumeTool)
        assertTrue(AgentObservedOutcomeEvidence.missing(listOf(requirement), listOf(action(volumeTool, observed))).isEmpty())
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(requirement),
            listOf(action(volumeTool, observed + ("stream" to "alarm")))).isEmpty())
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(requirement),
            listOf(action(volumeTool, observed), action(volumeTool, observed + ("state_verified" to false)))).isEmpty())
    }

    @Test fun unrelatedToolsKeepTheirExistingEvidence() {
        val raw = mapOf("readable" to true)
        assertSame(raw, AgentDeviceStateEvidence.normalize("galaxyssi.workspace.file.export", raw, false))
    }

    @Test fun partialPostconditionCannotOverrideAnExplicitUnverifiedReceipt() {
        val requirement = AgentObservedOutcome("volume", volumeTool, mapOf("/stream" to "music"),
            mapOf("/volume" to 8))
        assertTrue(AgentObservedOutcomeEvidence.missing(listOf(requirement),
            listOf(action(volumeTool, observed))).isEmpty())
        assertFalse(AgentObservedOutcomeEvidence.missing(listOf(requirement),
            listOf(action(volumeTool, observed + ("state_verified" to false)))).isEmpty())
    }

    private fun result(tool: String, output: AgentNativeJsonObject) = AgentActionResult("fixture", true, "fixture",
        mapOf("native_tool_id" to tool, "native_tool_output" to AgentNativeJsonCodec.stringify(output)) + AgentGoalEvidence.metadata(output))

    private fun action(tool: String, output: AgentNativeJsonObject) = AgentAction("fixture", AgentActionKind.CALL_NATIVE_TOOL,
        tool, AgentRisk.LOW, AgentActionStatus.COMPLETED, "fixture", mapOf("tool_id" to tool), evidence = AgentNativeJsonCodec.stringify(output))
}
