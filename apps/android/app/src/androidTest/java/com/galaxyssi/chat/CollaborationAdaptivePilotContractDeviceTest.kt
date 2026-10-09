package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.lang.reflect.Modifier
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Checks discovery without invoking the guarded real-model trial. */
@RunWith(AndroidJUnit4::class)
class CollaborationAdaptivePilotContractDeviceTest {
    @Test fun singleCalibrationUsesOneUnstagedMemberWithAndroidJson() {
        val raw = JSONObject().put("format", CollaborationAdaptivePilotPlan.SINGLE_FORMAT)
            .put("pilot_id", "single-device-contract").put("device_model", android.os.Build.MODEL)
            .put("target_id", "fixture:codex").put("model_id", "selected-model").put("reasoning_effort", "high")
            .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("goal", "Synthetic contract check only")
            .put("trial_timeout_ms", 1_000).put("maximum_dispatches", 1)
            .put("members", JSONArray().put(JSONObject().put("id", "solo").put("name", "Solo").put("role", "Researcher")))
        val plan = CollaborationAdaptivePilotPlan.from(raw, 1, 1_000)
        val definition = plan.definition("contract-fixture", "contract-run")
        assertEquals(1, definition.members.size)
        assertEquals(plan.goal, definition.members.single().objective)
        assertTrue(plan.matchesExecution(definition.members.single(), definition))
        assertTrue(!CollaborationLiveGraph.enabled(definition))
        assertTrue(CollaborationResearchWorkflow.stage(definition.members.single()) == null)
    }

    @Test fun productionCoordinatorPromptFitsWithAndroidJsonAndFullDirectory() {
        val rows = object : CollaborationGoalContractRows {
            val values = mutableMapOf<String, String>()
            override fun read(key: String) = values[key]
            override fun commit(values: Map<String, String>) { this.values.putAll(values) }
            override fun removePrefix(prefix: String) { values.keys.removeAll { it.startsWith(prefix) } }
        }
        val store = CollaborationGoalContractStore(rows, { true })
        val member = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND,
            instanceId = "lead", context = mapOf("collaboration_group_id" to "prompt-smoke"))), "goal").single()
        val request = AgentRunRequest("prompt-smoke", "turn", "task", runId = "child", parentRunId = "run", goal = "Complete original goal ".repeat(5000),
            context = mapOf(CollaborationGoalLoop.CRITERIA to "[]", "collaboration_research_roster" to "roster ".repeat(5000),
                CollaborationGoalLoop.PREVIOUS to "assessment ".repeat(5000), CollaborationResourceRecovery.FEEDBACK to "resource ".repeat(5000)))
        val execution = AgentTeamMemberExecutionContext(member, request,
            AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 0, AgentSubagentProvenance())
        val prompt = CollaborationResearchPrompt.prepare(execution, store,
            evolution = { "saved evolution directory" }, problems = { "saved problem directory" },
            capabilities = { "saved capability directory" }) { "history ".repeat(5000) }
        assertTrue(prompt.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
        assertTrue(prompt.contains(CollaborationGoalLoop.instructions()))
        assertTrue(prompt.contains("mode=evolution_rules"))
        val restored = CollaborationResearchPrompt.prepare(execution, store) { error("Retry must use saved context") }
        assertTrue(restored.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
        assertTrue(restored.contains("mode=goal_contract"))
        android.util.Log.i("ResearchPromptSmoke", "coordinator=${prompt.length} restored=${restored.length}")
    }

    @Test fun adaptiveEntryIsAValidJUnit4Method() {
        val method = CollaborationAdaptivePilotDeviceTest::class.java.getDeclaredMethod("runAdaptiveRemotePilot")
        assertTrue(method.isAnnotationPresent(Test::class.java))
        assertTrue(Modifier.isPublic(method.modifiers))
        assertEquals(0, method.parameterCount)
        assertEquals(Void.TYPE, method.returnType)
    }
}
