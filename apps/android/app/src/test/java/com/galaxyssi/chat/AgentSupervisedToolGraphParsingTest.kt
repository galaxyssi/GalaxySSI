package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedToolGraphParsingTest {
    @Test fun `real phone inspect plan parses without being admitted as a code project tool`() {
        val tool = descriptor(AgentPhoneUiNativeTools.INSPECT, AgentNativeToolConcurrency.SERIAL)
        val screen = ScreenContext("test.fixture", pageTitle = "Fixture")
        val request = AgentRequest("Inspect the current phone App", screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "phone-parser", goal = "Inspect the current phone App",
                screen = screen, permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = listOf(tool)))
        val source = """{"execution_location":"phone","actions":[{"kind":"CALL_NATIVE_TOOL","target":"galaxyssi.phone.ui.inspect","parameters":{"tool_id":"galaxyssi.phone.ui.inspect","arguments":{"offset":0,"limit":80}}}]}"""
        val plan = requireNotNull(AgentModelPlanParser.parse(request, source, settings))
        val site = AgentExecutionSiteDecision(AgentRequestedExecutionSite.PHONE)
        assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(site, plan.actions))
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(site, plan.actions, phoneControl = true))
    }
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

    @Test fun `valid file graph has no rejection and unchanged legacy parser semantics`() {
        val source = plan(action(1, write.id), action(2, read.id, 1))
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), source, settings)
        assertNotNull(result.plan)
        assertNull(result.rejection)
        assertEquals(AgentModelPlanParser.parse(request(), source, settings)!!.actions, result.plan!!.actions)
    }

    @Test fun `completion must follow file receipts instead of sharing their batch`() {
        val completion = JSONObject().put("kind", "DRAFT_PLAN").put("target", "task-complete")
        val source = plan(action(1, write.id), completion)
        val result = AgentModelPlanParser.parseWithDiagnostics(request().copy(replanReason = "Review prior result"), source, settings)
        assertNull(result.plan)
        assertEquals("completion_mixed_with_execution", result.rejection!!.code)
        assertEquals("actions", result.rejection!!.field)
        assertTrue(result.rejection!!.detail.contains("next response"))
        val repair = AgentSupervisedProjectLoop.formatRepairPrompt(request(), source, result.rejection!!.toJson())
        assertTrue(repair.contains("completion_mixed_with_execution"))
        assertTrue(repair.contains("Never mix DRAFT_PLAN/task-complete"))
    }

    @Test fun `unknown tool feedback identifies inventory failure not invalid JSON`() {
        val source = plan(action(1, "galaxyssi.unavailable.fixture"))
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), source, settings)
        assertEquals("native_tool_unavailable", result.rejection!!.code)
        assertEquals("actions[0].parameters.tool_id", result.rejection!!.field)
        assertTrue(result.rejection!!.detail.contains("galaxyssi.unavailable.fixture"))
        assertNull(result.plan)
    }

    @Test fun `dependency feedback identifies the rejected field and preserves all or nothing admission`() {
        val source = plan(action(1, write.id), action(2, read.id, 7))
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), source, settings)
        assertNull(result.plan)
        assertEquals("invalid_dependency", result.rejection!!.code)
        assertEquals("actions[1].depends_on", result.rejection!!.field)
        assertTrue(result.rejection!!.detail.contains("Available earlier refs: step-1"))
        assertTrue(result.rejection!!.detail.contains("not id, target, tool IDs"))
    }

    @Test fun `an id or display target cannot silently replace an action ref`() {
        val first = action(1, write.id).put("id", "invented-id").put("target", "Displayed title")
        for (invalid in listOf("invented-id", "Displayed title", write.id, "model-1-step-1")) {
            val next = action(2, read.id).put("depends_on", JSONArray().put(invalid))
            val rejected = AgentModelPlanParser.parseWithDiagnostics(request(), plan(first, next), settings)
            assertNull(rejected.plan)
            assertEquals("invalid_dependency", rejected.rejection!!.code)
            assertTrue(rejected.rejection!!.detail.endsWith("Available earlier refs: step-1"))
        }
        assertNotNull(AgentModelPlanParser.parse(request(), plan(first, action(2, read.id, 1)), settings))
    }


    @Test fun `native output substitution returns actionable feedback`() {
        val source = plan(action(1, write.id), action(2, read.id, 1)
            .put("use_outputs_from", JSONArray().put("step-1")))
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), source, settings)
        assertEquals("native_output_substitution", result.rejection!!.code)
        assertEquals("actions[1].use_outputs_from", result.rejection!!.field)
    }

    @Test fun `invalid syntax and malformed requirements have distinct reasons`() {
        assertEquals("invalid_json", AgentModelPlanParser.parseWithDiagnostics(request(), "not json", settings).rejection!!.code)
        val source = JSONObject(plan(action(1, read.id))).put("completion_requirements", "bad").toString()
        assertEquals("invalid_requirements", AgentModelPlanParser.parseWithDiagnostics(request(), source, settings).rejection!!.code)
    }

    @Test fun `batch feedback reports the effective bound without truncating the plan`() {
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), plan(action(1, write.id), action(2, read.id, 1)),
            AgentModelPlannerSettings(maxActions = 1))
        assertNull(result.plan)
        assertEquals("batch_size", result.rejection!!.code)
        assertTrue(result.rejection!!.detail.contains("Received 2"))
        assertTrue(result.rejection!!.detail.contains("1..1"))
    }

    @Test fun `duplicate references are diagnosed before any execution`() {
        val result = AgentModelPlanParser.parseWithDiagnostics(request(), plan(action(1, write.id), action(1, read.id)), settings)
        assertNull(result.plan)
        assertEquals("duplicate_ref", result.rejection!!.code)
        assertEquals("actions[1].ref", result.rejection!!.field)
    }

    @Test fun `requested results survive parsing and cannot disappear during a repair`() {
        val original = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, results = listOf(
            AgentGoalResultRequirement("first", "First requested result"),
            AgentGoalResultRequirement("second", "Second requested result")))
        val source = JSONObject(plan(action(1, read.id))).put("completion_requirements", original.toJson()).toString()
        assertEquals(original, AgentModelPlanParser.parse(request(), source, settings)?.completionRequirements)
        val dropped = original.copy(results = original.results.take(1), reason = "Only the first result is ready")
        val correction = JSONObject(source).put("completion_requirements", dropped.toJson()).toString()
        val rejected = AgentModelPlanParser.parseWithDiagnostics(request().copy(completionRequirements = original), correction, settings)
        assertNull(rejected.plan)
        assertEquals("unexplained_requirement_change", rejected.rejection!!.code)
        assertTrue(rejected.rejection!!.detail.contains("Do not drop unfinished requested results"))
    }

    @Test fun `invalid outcome identity reports the exact field without rejecting JSON syntax`() {
        val required = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false,
            outcomes = listOf(AgentObservedOutcome("value", read.id, mapOf("/scope" to "phone"), mapOf("/value" to 2))))
        val json = required.toJson()
        json.getJSONArray("outcomes").getJSONObject(0).getJSONObject("subject").put("/observed_at_epoch_ms", 1234)
        val source = JSONObject(plan(action(1, read.id))).put("completion_requirements", json).toString()
        val rejection = AgentModelPlanParser.parseWithDiagnostics(request(), source, settings).rejection!!
        assertEquals("invalid_requirements", rejection.code)
        assertTrue(rejection.detail.contains("outcomes[0].subject[/observed_at_epoch_ms]"))
        assertTrue(rejection.detail.contains("requires a string identity value"))
        assertTrue(rejection.detail.contains("JSON syntax is valid"))
        json.getJSONArray("outcomes").getJSONObject(0).getJSONObject("subject").remove("/observed_at_epoch_ms")
        assertNotNull(AgentModelPlanParser.parse(request(), JSONObject(source).put("completion_requirements", json).toString(), settings))
    }

    @Test fun `completion answers are not truncated to an ordinary action label`() {
        val answer = "First requested result. ".repeat(30) + "\nFinal requested result must remain visible."
        val completion = JSONObject().put("kind", "DRAFT_PLAN").put("target", "task-complete")
            .put("description", answer).put("parameters", JSONObject())
        val parsed = AgentModelPlanParser.parse(request().copy(replanReason = "Observed all requested results"),
            plan(completion), settings)!!
        assertEquals(answer, parsed.actions.single().description)
        val executable = action(1, read.id).put("description", answer)
        assertEquals(300, AgentModelPlanParser.parse(request(), plan(executable), settings)!!.actions.single().description.length)
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
