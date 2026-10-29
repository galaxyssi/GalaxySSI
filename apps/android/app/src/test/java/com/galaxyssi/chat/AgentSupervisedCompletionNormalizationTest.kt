package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedCompletionNormalizationTest {
    private val answer = "\u67e5\u8be2\u7ed3\u679c\u5982\u4e0b\u3002\n\n[\u6765\u6e90](https://example.com/source)"
    private val screen = ScreenContext("fixture", pageTitle = "Completion")
    private val request = AgentRequest("Explain the result", screen, emptyList(), memories = emptyList(),
        runtimeContext = AgentRuntimeContextBuilder.build("completion-test", "Explain the result", screen,
            PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList()))
    private val settings = AgentSupervisedProjectLoop.plannerSettings(AgentModelPlannerSettings())

    private fun action(kind: String) = JSONObject().put("kind", kind).put("description", answer)
    private fun envelope(vararg actions: JSONObject, site: String = "phone") = JSONObject()
        .put("execution_location", site).put("actions", JSONArray(actions.toList())).toString()
    private fun normalizedAction(source: JSONObject) = JSONObject(AgentSupervisedProjectControlPayload.normalize(
        envelope(source), emptyList())).getJSONArray("actions").getJSONObject(0)

    @Test fun completionAliasesBecomeOneAnswerOnlyActionWithoutChangingItsContent() {
        for (kind in listOf("task-complete", "TASK_COMPLETE", "Task-Complete")) {
            for (parameters in listOf<JSONObject?>(null, JSONObject())) {
                val source = action(kind).put("completes_goal", true)
                    .apply { if (parameters != null) put("parameters", parameters) }
                val normalized = AgentSupervisedProjectControlPayload.normalize(envelope(source), emptyList())
                val parsed = AgentModelPlanParser.parseWithDiagnostics(request, normalized, settings, allowInitialCompletion = true)
                assertNotNull("$kind: ${parsed.rejection}", parsed.plan)
                val completion = parsed.plan!!.actions.single()
                assertTrue(completion.isTaskCompleteMarker())
                assertEquals(answer, completion.description)
            }
        }
    }

    @Test fun executableParametersAndUnknownFieldsAreNotDiscardedByCompletionAliases() {
        for (source in listOf(
            action("TASK_COMPLETE").put("parameters", JSONObject().put("command", "echo fixture")),
            action("TASK_COMPLETE").put("parameters", "invalid"),
            action("TASK_COMPLETE").put("tool_calls", JSONArray().put(JSONObject().put("name", "execute"))),
            action("TASK_COMPLETE").put("target", "phone-command"),
            action("TASK_COMPLETE").put("description", "")
        )) assertEquals("TASK_COMPLETE", normalizedAction(source).getString("kind"))
    }

    @Test fun mixedActionsAndExplicitExecutionSitesRemainUnchanged() {
        val mixed = envelope(action("TASK_COMPLETE"), action("CALL_NATIVE_TOOL").put("target", "fixture"))
        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(mixed, emptyList()))
        assertEquals(2, normalized.getJSONArray("actions").length())
        assertEquals("TASK_COMPLETE", normalized.getJSONArray("actions").getJSONObject(0).getString("kind"))
        assertEquals("desktop", JSONObject(AgentSupervisedProjectControlPayload.normalize(
            envelope(action("TASK_COMPLETE"), site = "desktop"), emptyList())).getString("execution_location"))
    }

    @Test fun directCompletionPreservesTextAndInheritsRequiredEvidence() {
        val required = AgentCompletionRequirements(AgentPublicationRequirement.PULL_REQUEST, true)
        for (response in listOf(answer, JSONObject().put("disposition", "respond").put("final_response", answer).toString())) {
            val normalized = requireNotNull(AgentSupervisedProjectDirectResponseCodec.completionPlan(response))
            val parsed = AgentModelPlanParser.parseWithDiagnostics(request.copy(replanReason = "Review observations",
                completionRequirements = required), normalized, settings).plan!!
            assertEquals(required, parsed.completionRequirements)
            assertEquals(answer, parsed.actions.single().description)
            assertTrue(parsed.actions.single().isTaskCompleteMarker())
            assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(parsed.completionRequirements, emptyList()).isNotEmpty())
        }
    }

    @Test fun invalidControlResponsesAreNotConvertedToFinalAnswers() {
        for (response in listOf("", "{", "{}", "{\"disposition\":\"respond\",\"final_response\":\"\"}",
            envelope(action("CALL_NATIVE_TOOL")), "<DSML><invoke name=\"search\">query</invoke></DSML>")) {
            assertNull(response, AgentSupervisedProjectDirectResponseCodec.completionPlan(response))
        }
    }

    @Test fun repairPromptAllowsAnswerDeliveryWithoutRepeatingResearch() {
        val prompt = AgentSupervisedProjectLoop.formatRepairPrompt(request, "{}", "action_plan")
        assertTrue(prompt.contains("\"disposition\":\"respond\""))
        assertTrue(prompt.contains("preserve the answer's facts and sources"))
        assertTrue(prompt.contains("Unexecuted tool markup is not evidence"))
    }

    @Test fun answerOnlyHistoryRequiresKnownCompletedReadOnlyTools() {
        val read = AgentNativeToolDescriptor("fixture-read", "1.0.0", "Read", "Read fixture",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW, effect = AgentNativeToolEffect.READ_ONLY)
        val action = AgentAction("read", AgentActionKind.CALL_NATIVE_TOOL, read.id, AgentRisk.LOW,
            AgentActionStatus.COMPLETED, "Read fixture", parameters = mapOf("tool_id" to read.id))
        assertTrue(AgentCompletionEvidenceHistory.isAnswerOnly(emptyList()) { null })
        assertTrue(AgentCompletionEvidenceHistory.isAnswerOnly(listOf(action)) { read })
        assertFalse(AgentCompletionEvidenceHistory.isAnswerOnly(listOf(action)) { read.copy(effect = AgentNativeToolEffect.MUTATION) })
        assertFalse(AgentCompletionEvidenceHistory.isAnswerOnly(listOf(action)) { null })
        assertFalse(AgentCompletionEvidenceHistory.isAnswerOnly(listOf(action.copy(status = AgentActionStatus.FAILED))) { read })
        assertFalse(AgentCompletionEvidenceHistory.isAnswerOnly(listOf(action.copy(kind = AgentActionKind.SET_ALARM))) { read })
    }
}
