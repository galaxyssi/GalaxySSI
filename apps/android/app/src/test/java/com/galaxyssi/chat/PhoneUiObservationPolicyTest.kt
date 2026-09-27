package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class PhoneUiObservationPolicyTest {
    private fun window(id: Int, pkg: String = "browser", app: Boolean = true, focused: Boolean = false,
        active: Boolean = false, layer: Int = 0) = PhoneUiWindowCandidate(id, pkg, app, focused, active, layer)
    @Test fun overlaysAndKeyboardCannotReplaceTarget() {
        assertEquals(1, PhoneUiObservationPolicy.select(listOf(window(1), window(2, "own", false, true, true, 9),
            window(3, "keyboard", false, true, true, 10)), "own", true))
    }
    @Test fun promptActivityCannotReplaceExternalApp() {
        assertEquals(1, PhoneUiObservationPolicy.select(listOf(window(1), window(2, "own", focused = true, layer = 9)), "own", true))
    }
    @Test fun focusedSplitScreenAppWinsOverLayer() {
        assertEquals(1, PhoneUiObservationPolicy.select(listOf(window(1, focused = true), window(2, layer = 9)), "own", true))
    }
    @Test fun foregroundAppCanReadOwnWindowOutsideAssistantTask() {
        assertEquals(2, PhoneUiObservationPolicy.select(listOf(window(1), window(2, "own", focused = true)), "own", false))
    }
    @Test fun unavailableTargetDoesNotFallBackToAssistant() {
        assertNull(PhoneUiObservationPolicy.select(listOf(window(2, "own", focused = true)), "own", true))
    }
    @Test fun staleRevisionOrWindowIsRejected() {
        assertTrue(PhoneUiObservationPolicy.accepts(1, "r1", 1, "r1"))
        assertFalse(PhoneUiObservationPolicy.accepts(1, "r1", 1, "r2"))
        assertFalse(PhoneUiObservationPolicy.accepts(1, "r1", 2, "r1"))
        assertFalse(PhoneUiObservationPolicy.accepts(-1, "", -1, ""))
    }
    @Test fun systemAuthorizationMustBeHandledByTheUser() {
        assertFalse(PhoneUiObservationPolicy.canMutatePackage("com.android.permissioncontroller"))
        assertFalse(PhoneUiObservationPolicy.canMutatePackage("com.android.systemui"))
        assertTrue(PhoneUiObservationPolicy.canMutatePackage("com.android.chrome"))
    }
    @Test fun sensitiveActionsRequireConfirmationButReadingAndTypingDoNot() {
        listOf("Send", "Delete", "Pay now", "\u53d1\u9001", "\u5220\u9664", "\u652f\u4ed8").forEach {
            assertTrue(PhoneUiMutationRisk.requiresConfirmation("click", it, ""))
        }
        assertTrue(PhoneUiMutationRisk.requiresConfirmation("long_click", "", "Transfer"))
        assertFalse(PhoneUiMutationRisk.requiresConfirmation("set_text", "Send", ""))
        assertFalse(PhoneUiMutationRisk.requiresConfirmation("click", "Search", ""))
    }
    @Test fun nodePagesHaveBoundedStableOffsetsAndDoNotDuplicateItems() {
        val nodes = (0..249).map { PhoneUiNode("0/$it", "$it", "", "", "Text", "0,0,10,10",
            false, false, false, false, true, null, false) }
        val snapshot = PhoneUiSnapshot(1, "browser", "revision", nodes, false, 1L)
        assertEquals(100, (snapshot.page(0, 1_000)["nodes"] as List<*>).size)
        assertEquals(100, snapshot.page(0, 100)["next_offset"])
        assertEquals(200, snapshot.page(100, 100)["next_offset"])
        assertNull(snapshot.page(200, 100)["next_offset"])
        assertTrue((snapshot.page(999, 80)["nodes"] as List<*>).isEmpty())
    }

    @Test fun latestFrameSurvivesLargeNodePageTruncation() {
        val snapshot = largeSnapshot()
        val output = AgentNativeJsonCodec.stringify(snapshot.page())
        assertTrue(output.length > 4_000)
        val prefix = output.take(4_000)
        assertTrue(prefix.startsWith("{\"_frame\":"))
        assertTrue(prefix.contains("\"revision\":\"${snapshot.revision}\""))
        assertTrue(prefix.contains("\"window_id\":42"))
        assertTrue(prefix.contains("\"package_name\":\"browser\""))
    }

    @Test fun mutationReceiptHandoffKeepsFreshFrameWithoutIncreasingEvidenceBudget() {
        val snapshot = largeSnapshot()
        val output = AgentNativeJsonCodec.stringify(linkedMapOf(
            "_frame" to snapshot.frame(), "accepted" to true, "observation" to snapshot.page()
        ))
        val inspect = AgentAction(id = "inspect", kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentPhoneUiNativeTools.ACT, description = "Click fixture", risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED, evidence = output)
        val continuation = AgentAction(id = "continue", kind = AgentActionKind.CALL_CONNECTOR,
            target = "model", description = "Continue from fresh UI", risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            parameters = mapOf("use_outputs_from" to inspect.id))
        val plan = AgentPlan(goal = "Control fixture", screen = ScreenContext("browser", pageTitle = "Fixture"), steps = emptyList(),
            actions = listOf(inspect, continuation))
        val prompt = plan.materializeToolInput(continuation, true).parameters.getValue("prompt")
        assertTrue(prompt.contains("\"revision\":\"${snapshot.revision}\""))
        assertTrue(prompt.contains("\"window_id\":42"))
        assertFalse(prompt.contains(output))
        assertTrue(prompt.length < 4_500)
    }

    private fun largeSnapshot() = PhoneUiSnapshot(42, "browser", "0123456789abcdef".repeat(4),
        (0..249).map { PhoneUiNode("0/$it", "Fixture row $it " + "x".repeat(100), "", "", "Text",
            "0,0,10,10", false, false, false, false, true, null, false) }, false, 1L)
}
