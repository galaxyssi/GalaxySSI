package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedToolGraphParsingTest {
    private val write = descriptor(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, AgentNativeToolConcurrency.SERIAL)
    private val read = descriptor(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
    private val descriptors = listOf(write, read).associateBy { it.id }
    private val settings = AgentSupervisedProjectLoop.plannerSettings(AgentModelPlannerSettings(maxActions = 1, maxAgentHops = 1))

    @Test fun `negative publication goal does not acquire host guessed commit requirements`() {
        val goal = "\u53ea\u5728\u624b\u673a\u64cd\u4f5c\uff0c\u4e0d\u63d0\u4ea4\u4ee3\u7801\uff0c\u4e0d\u53d1\u5e03\uff0c\u4e0d\u9700\u8981\u5b89\u88c5\u8f6f\u4ef6\u3002"
        val local = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)
        val source = JSONObject(plan(action(1, write.id))).put("completion_requirements", local.toJson()).toString()
        val parsed = requireNotNull(AgentModelPlanParser.parse(request().copy(goal = goal), source, settings))
        assertEquals(local, parsed.completionRequirements)
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(parsed.completionRequirements, emptyList()).isEmpty())
    }

    @Test fun `omitted declarations inherit current plan but malformed declarations are rejected`() {
        val source = plan(action(1, write.id))
        val previous = AgentCompletionRequirements(AgentPublicationRequirement.PULL_REQUEST, true)
        val continuation = request().copy(completionRequirements = previous)
        assertEquals(previous, AgentModelPlanParser.parse(continuation, source, settings)!!.completionRequirements)
        assertNull(AgentModelPlanParser.parse(request(), source, settings)!!.completionRequirements)
        for (invalid in listOf<Any>(JSONObject.NULL, "none", JSONObject(), JSONObject()
            .put("publication", "none").put("phone_linux", "false"))) {
            assertNull(AgentModelPlanParser.parse(continuation, JSONObject(source)
                .put("completion_requirements", invalid).toString(), settings))
        }
    }

    @Test fun `model can correct publication interpretation with an explanation`() {
        val previous = AgentCompletionRequirements(AgentPublicationRequirement.COMMIT, false)
        val corrected = previous.copy(publication = AgentPublicationRequirement.NONE)
        val source = JSONObject(plan(action(1, write.id)))
        val continuation = request().copy(completionRequirements = previous)
        assertNull(AgentModelPlanParser.parse(continuation,
            source.put("completion_requirements", corrected.toJson()).toString(), settings))
        val explained = corrected.copy(reason = "The user explicitly excluded committing code.")
        assertEquals(explained, AgentModelPlanParser.parse(continuation,
            source.put("completion_requirements", explained.toJson()).toString(), settings)!!.completionRequirements)
    }

    @Test fun `real corrected Codex write and dependent read survives parsing remapping and scheduling`() {
        val source = plan(action(1, write.id), action(2, read.id, 1).put("completes_goal", true))
        val parsed = requireNotNull(AgentModelPlanParser.parse(request(), source, settings))
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(AgentExecutionSiteDecision(AgentRequestedExecutionSite.PHONE), parsed.actions))
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(parsed.actions, "current", descriptors::get))
        val ids = parsed.actions.associate { it.id to "revision-2-${it.id}" }
        val revised = parsed.copy(actions = parsed.actions.map { it.remapToolGraphIds(ids.getValue(it.id), ids) })
        assertTrue(AgentPlanValidator.validate(revised).valid)
        assertEquals(listOf(revised.actions.first().id), revised.runnableActions().map { it.id })
        assertEquals(listOf(revised.actions.first().id), revised.actions.last().dependencyIds())
        val completed = revised.copy(actions = listOf(revised.actions.first().copy(status = AgentActionStatus.COMPLETED), revised.actions.last()))
        assertEquals(listOf(revised.actions.last().id), completed.runnableActions().map { it.id })
    }

    @Test fun `unsupported native output substitution is rejected rather than silently ignored`() {
        val invalid = plan(action(1, write.id), action(2, read.id, 1).put("use_outputs_from", JSONArray().put("step-1")))
        assertNull(AgentModelPlanParser.parse(request(), invalid, settings))
        val repair = AgentSupervisedProjectLoop.formatRepairPrompt(request(), invalid, "action_plan")
        assertTrue(repair.contains("Runtime rejection: action_plan"))
        assertTrue(repair.contains("Native actions must leave use_outputs_from empty"))
    }

    @Test fun `advertised sixty four action graph passes parser and batch admission`() {
        val actions = (1..64).map { action(it, write.id, if (it > 1) it - 1 else null) }
        val parsed = requireNotNull(AgentModelPlanParser.parse(request(), plan(*actions.toTypedArray()), settings))
        assertEquals(64, parsed.toolGraphDepth())
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(parsed.actions, "current", descriptors::get))
        assertNull(AgentModelPlanParser.parse(request(), plan(*(actions + action(65, read.id, 64)).toTypedArray()), settings))
    }

    @Test fun `ordinary planner settings still control its own graph size`() {
        assertNull(AgentModelPlanParser.parse(request(), plan(action(1, write.id), action(2, read.id, 1)),
            AgentModelPlannerSettings(maxActions = 1)))
    }

    private fun action(index: Int, tool: String, dependency: Int? = null): JSONObject = JSONObject()
        .put("ref", "step-$index").put("kind", "CALL_NATIVE_TOOL").put("target", tool)
        .put("description", "Execute fixture step $index")
        .put("depends_on", JSONArray().apply { dependency?.let { put("step-$it") } })
        .put("use_outputs_from", JSONArray())
        .put("parameters", JSONObject().put("tool_id", tool).put("arguments", JSONObject()
            .put("workspace_id", "current").put("path", "fixture/result.txt")
            .put("text", "public fixture").put("create_parents", true)))

    private fun plan(vararg actions: JSONObject): String = JSONObject().put("execution_location", "phone")
        .put("actions", JSONArray(actions.toList())).toString()

    private fun request(): AgentRequest {
        val screen = ScreenContext("Test", pageTitle = "Test")
        return AgentRequest("Write then read a phone file", screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "graph-test", goal = "Write then read a phone file",
                screen = screen, permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = descriptors.values.toList()))
    }

    private fun descriptor(id: String, concurrency: AgentNativeToolConcurrency) = AgentNativeToolDescriptor(
        id, "1.0.0", id, "Fixture workspace tool", AgentNativeToolLocation.APPLICATION,
        AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
        capabilities = setOf("workspace.file.bounded"), idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = concurrency)
}
