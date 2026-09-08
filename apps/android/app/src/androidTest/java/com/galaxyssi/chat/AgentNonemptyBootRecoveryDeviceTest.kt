package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentNonemptyBootRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun sessions(id: String) = SharedPreferencesAgentSessionStore(context, "task:$id")

    @Test fun resumeDispatchesReadyDependencyWithoutReexecutingCompletedNode() {
        val id = "test-ready-resume-${UUID.randomUUID()}"
        try {
            val first = prepare(id)
            val restored = MobileNativeAgent(context, sessionStore = sessions(id))
            val result = restored.resumeCurrentTask()
            assertEquals(result.lastActionResult.toString(), AgentPhase.COMPLETED, result.phase)
            assertFinished(id, fingerprint(first))
        } finally { cleanup(id) }
    }

    @Test fun continueDispatchesProposedNodesWhilePlanning() {
        val id = "test-ready-continue-${UUID.randomUUID()}"
        try {
            val first = prepare(id, phase = AgentPhase.PLANNING)
            val result = MobileNativeAgent(context, sessionStore = sessions(id)).continueCurrentTask()
            assertEquals(result.lastActionResult.toString(), AgentPhase.COMPLETED, result.phase)
            assertFinished(id, fingerprint(first))
        } finally { cleanup(id) }
    }

    @Test fun cancelledSessionNeverDispatchesTheRemainingNode() {
        val id = "test-ready-cancel-${UUID.randomUUID()}"
        try {
            prepare(id, phase = AgentPhase.CANCELLED)
            val runtime = MobileNativeAgent(context, sessionStore = sessions(id))
            val result = runtime.resumeCurrentTask()
            assertEquals(AgentPhase.CANCELLED, result.phase)
            assertEquals(AgentActionStatus.PROPOSED, result.plan!!.actions.last().status)
            assertEquals(1, result.plan.checkpoints.size)
        } finally { cleanup(id) }
    }

    @Test fun publishNonemptyTaskForRealReboot() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonempty_boot_prepare") == "true")
        check(sessions(BOOT_ID).load() == null) { "Inspect the previous boot test before preparing another" }
        val first = prepare(BOOT_ID, phase = AgentPhase.EXECUTING)
        AgentEncryptedPreferences(context, "nonempty_boot_test_evidence").writeString(BOOT_ID,
            JSONObject().put("first", fingerprint(first)).put("boot_count", bootCount()).toString())
        EncryptedAgentWorkspaceStore(context).upsert(AgentWorkspace(
            BOOT_ID, BOOT_ID, BOOT_ID, BOOT_ID,
            goal = "\u7ee7\u7eed\u8bfb\u53d6\u624b\u673a\u5185\u5b58\u548c\u5b58\u50a8\u7a7a\u95f4",
            status = AgentWorkspaceStatus.RUNNING
        ))
        // End at an action boundary with a durable completed node and a ready dependent node.
        android.os.Process.killProcess(android.os.Process.myPid())
        fail("The process must terminate after checkpoint publication")
    }

    @Test fun verifyNonemptyTaskFinishedWithoutExplicitResume() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonempty_boot_verify") == "true")
        val store = EncryptedAgentWorkspaceStore(context)
        val deadline = android.os.SystemClock.elapsedRealtime() + 120_000L
        var workspace = store.find(BOOT_ID)!!
        while (!workspace.status.isTerminal && android.os.SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(250)
            workspace = store.find(BOOT_ID)!!
        }
        assertEquals(workspace.errorMessage + workspace.resultJson, AgentWorkspaceStatus.COMPLETED, workspace.status)
        val snapshot = sessions(BOOT_ID).load()!!
        assertEquals(AgentPhase.COMPLETED, snapshot.phase)
        val expected = AgentEncryptedPreferences(context, "nonempty_boot_test_evidence").readString(BOOT_ID, "")
        val evidence = JSONObject(expected)
        assertTrue(bootCount() > evidence.getInt("boot_count"))
        assertFinished(BOOT_ID, evidence.getString("first"))
        val bootAt = System.currentTimeMillis() - android.os.SystemClock.elapsedRealtime()
        assertTrue(snapshot.currentPlan!!.checkpoints.single { it.actionId == "storage" }.createdAtMillis >= bootAt)
        assertTrue(workspace.toolCalls.any { it.id == "storage" && it.status == AgentToolCallStatus.SUCCEEDED })
        assertTrue(workspace.eventJournal.any { it.kind == "task.paused.process_restart" })
        assertTrue(workspace.resultJson.isNotBlank())
        // Keep the evidence until the explicit cleanup phase has been requested.
    }

    @Test fun clearCompletedBootFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonempty_boot_clear") == "true")
        check(EncryptedAgentWorkspaceStore(context).find(BOOT_ID)?.status == AgentWorkspaceStatus.COMPLETED)
        cleanup(BOOT_ID)
    }

    private fun prepare(id: String, phase: AgentPhase = AgentPhase.PAUSED): AgentAction {
        val runtime = MobileNativeAgent(context, sessionStore = sessions(id))
        runtime.sessionId = id
        runtime.currentGoal = "\u8bfb\u53d6\u624b\u673a\u5185\u5b58\u548c\u5b58\u50a8\u7a7a\u95f4"
        runtime.currentScreen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
        runtime.currentPlan = AgentPlan(runtime.currentGoal, runtime.currentScreen, emptyList(),
            listOf(action(id, "memory", AgentHardwareNativeTools.MEMORY_STATUS)),
            planId = id, confirmationRequired = false)
        runtime.phase = AgentPhase.PLANNING
        val firstState = runtime.executeFirstPendingAction()
        assertEquals(firstState.lastActionResult.toString(), AgentPhase.COMPLETED, firstState.phase)
        val plan = runtime.currentPlan!!
        val completed = plan.actions.single()
        assertNativeOutput(completed)
        val next = action(id, "storage", AgentHardwareNativeTools.STORAGE_STATUS).let {
            it.copy(parameters = it.parameters + ("depends_on" to "memory"))
        }
        runtime.currentPlan = plan.copy(actions = plan.actions + next)
        runtime.phase = phase
        runtime.lastActionResult = AgentActionResult("agent-interrupted", false, "Interrupted between nodes")
        runtime.persistSession()
        return completed
    }

    private fun action(id: String, actionId: String, tool: String) = AgentAction(
        actionId, AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, AgentActionStatus.PROPOSED,
        "\u8bfb\u53d6\u8bbe\u5907\u4fe1\u606f", mapOf("tool_id" to tool, "input_json" to "{}",
            INTERNAL_CONVERSATION_ID to id, INTERNAL_TURN_ID to id), requiresConfirmation = false)

    private fun assertFinished(id: String, original: String) {
        val snapshot = sessions(id).load()!!
        val plan = snapshot.currentPlan!!
        assertEquals(listOf("memory", "storage"), plan.actions.map { it.id })
        assertEquals(original, fingerprint(plan.actions.first()))
        assertTrue(plan.actions.all { it.status == AgentActionStatus.COMPLETED })
        plan.actions.forEach { action ->
            assertNativeOutput(action)
            assertEquals(1, plan.checkpoints.count { it.actionId == action.id })
            val key = AgentPlanNodeKey.from(id, plan, action)!!
            val observation = EncryptedAgentPlanNodeJournal(context).read(key)!!
            assertTrue(observation.verified)
            assertTrue(observation.result.success)
        }
        assertEquals("storage", snapshot.lastActionResult?.actionId)
    }

    private fun assertNativeOutput(action: AgentAction) {
        val output = JSONObject(action.evidence)
        assertTrue(output.getLong("total_bytes") > 0)
        assertTrue(output.getLong("available_bytes") >= 0)
    }

    private fun fingerprint(action: AgentAction): String = AgentNativeJsonCodec.sha256(mapOf(
        "id" to action.id, "status" to action.status.name, "parameters" to action.parameters,
        "result" to action.result, "evidence" to action.evidence))

    private fun bootCount(): Int = android.provider.Settings.Global.getInt(context.contentResolver,
        android.provider.Settings.Global.BOOT_COUNT, -1).also { check(it >= 0) }

    private fun cleanup(id: String) {
        val plan = sessions(id).load()?.currentPlan
        if (plan != null) AgentRunEventStore(context).removeRuns(plan.actions.mapNotNull {
            AgentPlanNodeKey.from(id, plan, it)?.let(EncryptedAgentPlanNodeJournal::runId)
        }.toSet())
        sessions(id).clear()
        val tasks = SQLiteAgentTaskStore(context)
        tasks.delete(tasks.forSession(id, 100).map { it.taskId }.toSet())
        EncryptedAgentWorkspaceStore(context).delete(id)
        AgentEncryptedPreferences(context, "nonempty_boot_test_evidence").removeDurably(id)
    }

    private companion object { const val BOOT_ID = "test-nonempty-boot-ready-dag" }
}
