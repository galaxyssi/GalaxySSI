package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProjectHistoryRetentionPolicyTest {
    @Test
    fun `long supervised project keeps lifecycle milestones beyond recent history`() {
        val branch = action("branch", AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        val mutation = action("mutation", AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT)
        val verification = action(
            id = "verification",
            toolId = AgentOnDeviceRuntimeTools.EXECUTE,
            input = JSONObject()
                .put("workspace_id", "current")
                .put("verification_kind", "test")
        )
        val routine = (1..48).map { index ->
            action("read-$index", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)
        }
        val plan = AgentPlan(
            planId = "long-project",
            goal = "Develop and publish the phone project",
            screen = ScreenContext(
                foregroundApp = "com.signalasi.chat",
                pageTitle = "SignalASI"
            ),
            steps = emptyList(),
            actions = emptyList(),
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            actionHistory = listOf(branch, mutation, verification) + routine
        )

        val retained = plan.historyForReplan()

        assertTrue(retained.any { it.id == branch.id })
        assertTrue(retained.any { it.id == mutation.id })
        assertTrue(retained.any { it.id == verification.id })
        assertEquals(40, retained.count { it.id.startsWith("read-") })
    }

    @Test
    fun `only the latest verified milestone of each lifecycle kind is retained`() {
        val oldCommit = action("old-commit", AgentMobileProjectNativeTools.COMMIT)
        val newCommit = action("new-commit", AgentMobileProjectNativeTools.COMMIT)
        val routine = (1..45).map { index ->
            action("routine-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
        }

        val retained = AgentProjectHistoryRetentionPolicy.retain(
            listOf(oldCommit, newCommit) + routine
        )

        assertTrue(retained.none { it.id == oldCommit.id })
        assertTrue(retained.any { it.id == newCommit.id })
        assertEquals(41, retained.size)
    }

    private fun action(
        id: String,
        toolId: String,
        input: JSONObject = JSONObject().put("workspace_id", "current")
    ) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = id,
        parameters = mapOf(
            "tool_id" to toolId,
            "input_json" to input.toString()
        ),
        result = "verified",
        requiresConfirmation = false
    )
}
