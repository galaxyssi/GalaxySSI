package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

class AgentSupervisedProjectPromptTest {
    @Test
    fun `supervised repair keeps the current provider below its rotation threshold`() {
        val connector = supervisedConnector(
            connectorId = "codex",
            fallbackIds = "cloud-models,hermes"
        )

        val route = AgentSupervisedProjectRepairRoutingPolicy.select(
            connector = connector,
            targets = supervisedTargets(),
            attempt = 1,
            rotateAfter = 2
        )

        assertFalse(route.rotated)
        assertEquals(1, route.attempt)
        assertEquals("codex", route.connector.parameters["connector_id"])
    }

    @Test
    fun `supervised repair rotates to the next configured provider and resets its attempts`() {
        val connector = supervisedConnector(
            connectorId = "codex",
            fallbackIds = "cloud-models,hermes"
        )

        val route = AgentSupervisedProjectRepairRoutingPolicy.select(
            connector = connector,
            targets = supervisedTargets(),
            attempt = 2,
            rotateAfter = 2
        )

        assertTrue(route.rotated)
        assertEquals(0, route.attempt)
        assertEquals("cloud-models", route.connector.parameters["connector_id"])
        assertEquals("Cloud Models", route.connector.target)
        assertEquals("model", route.connector.parameters["connector_kind"])
        assertEquals("cloud-model-api", route.connector.parameters["connector_adapter_type"])
        assertEquals("cloud-provider", route.connector.parameters["connector_failure_domain"])
        assertEquals("hermes,codex", route.connector.parameters["routing_fallback_ids"])
        assertEquals("0", route.connector.parameters["supervised_parse_attempt"])
        assertEquals("0", route.connector.parameters["supervised_progress_attempt"])
        assertEquals("0", route.connector.parameters["supervised_completion_attempt"])
        assertEquals("codex", route.connector.parameters["supervised_previous_connector_id"])
        assertEquals("1", route.connector.parameters["supervised_provider_rotation_count"])
    }

    @Test
    fun `manual provider selection never rotates during supervised repair`() {
        val connector = supervisedConnector(
            connectorId = "codex",
            fallbackIds = "cloud-models,hermes",
            manuallyLocked = true
        )

        val route = AgentSupervisedProjectRepairRoutingPolicy.select(
            connector = connector,
            targets = supervisedTargets(),
            attempt = 8,
            rotateAfter = 2
        )

        assertFalse(route.rotated)
        assertEquals(8, route.attempt)
        assertEquals("codex", route.connector.parameters["connector_id"])
    }

    @Test
    fun `supervised repair continues on the current provider when no fallback is callable`() {
        val connector = supervisedConnector(
            connectorId = "codex",
            fallbackIds = "offline-provider"
        )

        val route = AgentSupervisedProjectRepairRoutingPolicy.select(
            connector = connector,
            targets = supervisedTargets() + AgentCallableTarget(
                id = "offline-provider",
                title = "Offline Provider",
                kind = AgentConnectorKind.MODEL,
                status = AgentConnectorStatus.NEEDS_SETUP,
                capabilities = listOf(AgentCapability.CHAT)
            ),
            attempt = 5,
            rotateAfter = 2
        )

        assertFalse(route.rotated)
        assertEquals(5, route.attempt)
        assertEquals("codex", route.connector.parameters["connector_id"])
    }

    @Test
    fun `supervised repair rotates only within its supplied provider snapshot`() {
        val connector = supervisedConnector(
            connectorId = "codex",
            fallbackIds = "new-provider,cloud-models,hermes"
        )
        val requestSnapshot = supervisedTargets().filter { target ->
            target.id in setOf("codex", "cloud-models")
        }

        val route = AgentSupervisedProjectRepairRoutingPolicy.select(
            connector = connector,
            targets = requestSnapshot,
            attempt = 2,
            rotateAfter = 2
        )

        assertTrue(route.rotated)
        assertEquals("cloud-models", route.connector.parameters["connector_id"])
        assertFalse(route.connector.parameters["routing_fallback_ids"].orEmpty().contains("new-provider"))
        assertFalse(route.connector.parameters["routing_fallback_ids"].orEmpty().contains("hermes"))
    }

    @Test
    fun `canonicalizes unambiguous project tool dialect aliases`() {
        val raw = """
            {
              "execution_location":"phone",
              "actions":[
                {"ref":"branch","kind":"CALL_NATIVE_TOOL","target":"branch",
                 "depends_on":[],"use_outputs_from":[],
                 "parameters":{"tool_id":"signalasi.project.repository.branch","arguments":{
                   "workspace_id":"current","branch_name":"feature/test","base":"origin/main","create_new":true
                 }}}
              ]
            }
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
        val parameters = normalized.getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")
        val arguments = parameters.getJSONObject("arguments")

        assertEquals(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, parameters.getString("tool_id"))
        assertEquals("feature/test", arguments.getString("branch"))
        assertEquals("origin/main", arguments.getString("base_ref"))
        assertTrue(arguments.getBoolean("create"))
        assertFalse(arguments.has("branch_name"))
        assertFalse(arguments.has("base"))
        assertFalse(arguments.has("create_new"))
    }

    @Test
    fun `canonicalizes unambiguous workspace list dialect alias`() {
        val raw = """
            {
              "execution_location":"phone",
              "actions":[
                {"ref":"list","kind":"CALL_NATIVE_TOOL","target":"list",
                 "depends_on":[],"use_outputs_from":[],
                 "parameters":{"tool_id":"signalasi.workspace.files.list","arguments":{
                   "workspace_id":"current","path":""
                 }}}
              ]
            }
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
        val parameters = normalized.getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")

        assertEquals(AgentPhoneNativeToolCatalog.WORKSPACE_LIST, parameters.getString("tool_id"))
    }

    @Test
    fun `wraps an unambiguous single action object locally`() {
        val raw = """
            {"execution_location":"phone","summary":"Inspect the repository.","actions":
              {"ref":"inspect","kind":"CALL_NATIVE_TOOL","target":"signalasi.project.repository.inspect",
               "parameters":{"tool_id":"signalasi.project.repository.inspect","arguments":{"workspace_id":"current"}}}
            }
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
        val actions = normalized.getJSONArray("actions")

        assertEquals(1, actions.length())
        assertEquals("inspect", actions.getJSONObject(0).getString("ref"))
    }

    @Test
    fun `lifts direct native tool fields into the strict action schema locally`() {
        val raw = """
            {"execution_location":"phone","summary":"Inspect the repository.","action":
              {"ref":"inspect","tool_id":"signalasi.project.repository.inspect",
               "arguments":{"workspace_id":"current"}}
            }
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
        val action = normalized.getJSONArray("actions").getJSONObject(0)
        val parameters = action.getJSONObject("parameters")

        assertEquals(AgentActionKind.CALL_NATIVE_TOOL.name, action.getString("kind"))
        assertEquals("signalasi.project.repository.inspect", action.getString("target"))
        assertEquals("signalasi.project.repository.inspect", parameters.getString("tool_id"))
        assertEquals("current", parameters.getJSONObject("arguments").getString("workspace_id"))
        assertFalse(action.has("tool_id"))
        assertFalse(action.has("arguments"))
    }

    @Test
    fun `defaults a missing supervised execution location to phone locally`() {
        val raw = """
            {"summary":"Inspect the repository.","actions":[
              {"ref":"inspect","kind":"CALL_NATIVE_TOOL","target":"signalasi.project.repository.inspect",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.inspect","arguments":{"workspace_id":"current"}}}
            ]}
        """.trimIndent()

        val normalized = AgentSupervisedProjectControlPayload.normalize(raw)
        val json = JSONObject(normalized)

        assertEquals(AgentRequestedExecutionSite.PHONE.wireValue, json.getString("execution_location"))
        assertEquals("", json.optString("execution_location_evidence"))
        assertEquals(
            AgentRequestedExecutionSite.PHONE,
            AgentExecutionSiteDecisionCodec.parse(normalized, "Inspect the repository")?.site
        )
    }

    @Test
    fun `does not override an explicit desktop execution location`() {
        val raw = """
            {"execution_location":"desktop","execution_location_evidence":"on Desktop",
             "actions":[
              {"ref":"inspect","kind":"CALL_NATIVE_TOOL","target":"signalasi.project.repository.inspect",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.inspect","arguments":{"workspace_id":"current"}}}
            ]}
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))

        assertEquals(AgentRequestedExecutionSite.DESKTOP.wireValue, normalized.getString("execution_location"))
        assertEquals("on Desktop", normalized.getString("execution_location_evidence"))
    }

    @Test
    fun `moves flattened native tool parameters into arguments locally`() {
        val raw = """
            {"execution_location":"phone","actions":[
              {"ref":"read","parameters":{"tool_id":"signalasi.workspace.file.read.text",
               "workspace_id":"current","path":"README.md"}}
            ]}
        """.trimIndent()

        val action = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
            .getJSONArray("actions")
            .getJSONObject(0)
        val parameters = action.getJSONObject("parameters")
        val arguments = parameters.getJSONObject("arguments")

        assertEquals("signalasi.workspace.file.read.text", parameters.getString("tool_id"))
        assertEquals("current", arguments.getString("workspace_id"))
        assertEquals("README.md", arguments.getString("path"))
        assertFalse(parameters.has("workspace_id"))
        assertFalse(parameters.has("path"))
    }

    @Test
    fun `decodes native tool arguments encoded as a json object string`() {
        val raw = JSONObject()
            .put("execution_location", "phone")
            .put(
                "actions",
                org.json.JSONArray().put(
                    JSONObject()
                        .put("ref", "inspect")
                        .put(
                            "parameters",
                            JSONObject()
                                .put("tool_id", "signalasi.project.repository.inspect")
                                .put("arguments", "{\"workspace_id\":\"current\"}")
                        )
                )
            )
            .toString()

        val arguments = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
            .getJSONArray("actions")
            .getJSONObject(0)
            .getJSONObject("parameters")
            .getJSONObject("arguments")

        assertEquals("current", arguments.getString("workspace_id"))
    }

    @Test
    fun `canonicalizes repository status and branch name dialect aliases`() {
        val status = """
            {"execution_location":"phone","actions":[
              {"ref":"status","kind":"CALL_NATIVE_TOOL","target":"status",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.status","arguments":{"workspace_id":"current"}}}
            ]}
        """.trimIndent()
        val branch = """
            {"execution_location":"phone","actions":[
              {"ref":"branch","kind":"CALL_NATIVE_TOOL","target":"branch",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.branch","arguments":{
                 "workspace_id":"current","name":"feature/test"
               }}}
            ]}
        """.trimIndent()

        val statusParameters = JSONObject(AgentSupervisedProjectControlPayload.normalize(status))
            .getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")
        val branchParameters = JSONObject(AgentSupervisedProjectControlPayload.normalize(branch))
            .getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")

        assertEquals(AgentMobileProjectNativeTools.INSPECT, statusParameters.getString("tool_id"))
        assertEquals("feature/test", branchParameters.getJSONObject("arguments").getString("branch"))
        assertFalse(branchParameters.getJSONObject("arguments").has("name"))
    }

    @Test
    fun `canonicalizes repository history dialect alias`() {
        val raw = """
            {"execution_location":"phone","actions":[
              {"ref":"history","kind":"CALL_NATIVE_TOOL","target":"history",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.history","arguments":{"workspace_id":"current"}}}
            ]}
        """.trimIndent()

        val parameters = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
            .getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")

        assertEquals(AgentMobileProjectNativeTools.LOG, parameters.getString("tool_id"))
    }

    @Test
    fun `canonicalizes repository pull request dialect and branch arguments`() {
        val raw = """
            {"execution_location":"phone","actions":[
              {"ref":"pr","kind":"CALL_NATIVE_TOOL","target":"pull-request",
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.pull_request.create","arguments":{
                 "workspace_id":"current","title":"Improve safety",
                 "base_branch":"main","head_branch":"feature/safety"
               }}}
            ]}
        """.trimIndent()

        val parameters = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
            .getJSONArray("actions").getJSONObject(0).getJSONObject("parameters")
        val arguments = parameters.getJSONObject("arguments")

        assertEquals(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST, parameters.getString("tool_id"))
        assertEquals("main", arguments.getString("base"))
        assertEquals("feature/safety", arguments.getString("head"))
        assertFalse(arguments.has("base_branch"))
        assertFalse(arguments.has("head_branch"))
    }

    @Test
    fun `each model iteration rejects duplicate observation actions`() {
        val first = AgentAction(
            id = "inspect",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "signalasi.project.repository.inspect",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Inspect repository",
            requiresConfirmation = false
        )
        val second = first.copy(id = "build", description = "Build project")

        assertTrue(AgentSupervisedProjectLoop.acceptsIteration(listOf(first)))
        assertEquals(false, AgentSupervisedProjectLoop.acceptsIteration(listOf(first, second)))
    }

    @Test
    fun `repair plans do not count as semantically healthy model responses`() {
        val request = request("Inspect the phone project")
        val action = AgentAction(
            id = "inspect",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentMobileProjectNativeTools.INSPECT,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Inspect repository",
            requiresConfirmation = false
        )
        val executable = AgentPlanFactory.singleAction(request, action)
        val repair = AgentPlanFactory.singleAction(
            request,
            action.copy(
                parameters = mapOf(SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format")
            )
        )
        val executableWithInheritedReviewerMarker = executable.copy(
            actions = executable.actions + action.copy(
                id = "review",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "Codex",
                parameters = mapOf(SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format")
            )
        )

        assertTrue(AgentSupervisedProjectLoop.isExecutableResponsePlan(executable))
        assertTrue(AgentSupervisedProjectLoop.isExecutableResponsePlan(executableWithInheritedReviewerMarker))
        assertFalse(AgentSupervisedProjectLoop.isExecutableResponsePlan(repair))
        assertFalse(AgentSupervisedProjectLoop.isExecutableResponsePlan(null))
    }

    @Test
    fun `typed supervised decisions preserve the real rejection cause`() {
        val rejected = AgentSupervisedProjectPlanDecision.rejected(
            kind = "supervised_completion_evidence_missing",
            message = "Missing pull request URL",
            attempts = 3
        )

        assertEquals(AgentSupervisedProjectPlanDisposition.REJECTED, rejected.disposition)
        assertFalse(rejected.semanticallyExecutable)
        assertEquals("supervised_completion_evidence_missing", rejected.failureKind)
        assertEquals("Missing pull request URL", rejected.failureMessage)
        assertEquals(3, rejected.repairAttempts)
        assertEquals(null, rejected.plan)
    }

    @Test
    fun `prompt delegates completion intent to the model and evidence validation to Android`() {
        val prompt = AgentSupervisedProjectLoop.planningPrompt(
            request("Improve SignalASI and submit a pull request")
        )

        assertTrue(prompt.contains("\"completes_goal\":false"))
        assertTrue(prompt.contains("Set completes_goal=true only when"))
        assertTrue(prompt.contains("Android validates required publication and runtime evidence"))
    }

    @Test
    fun `project summaries are visible grounded and written in the user language`() {
        val prompt = AgentSupervisedProjectLoop.planningPrompt(request("Fix the Android build on this phone"))

        assertTrue(prompt.contains("same language as the user's goal"))
        assertTrue(prompt.contains("one to three short sentences"))
        assertTrue(prompt.contains("relevant observed evidence"))
        assertTrue(prompt.contains("never private chain-of-thought"))
        assertTrue(prompt.contains("one action, or 2-4 independent read-only"))
        assertTrue(prompt.contains("wait for the receipt"))
    }

    @Test
    fun `recovery summaries explain changed evidence and approach`() {
        val action = AgentAction(
            id = "build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "signalasi.runtime.execute",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the phone project",
            result = "Gradle dependency resolution failed",
            requiresConfirmation = false
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            request = request("Fix the Android build on this phone"),
            failedAction = action,
            reason = "The configured repository was unavailable"
        )

        assertTrue(prompt.contains("what changed"))
        assertTrue(prompt.contains("why"))
        assertTrue(prompt.contains("Gradle dependency resolution failed"))
    }

    @Test
    fun `recovery prompt does not duplicate failure evidence already in the progress ledger`() {
        val marker = "UNIQUE_RUNTIME_FAILURE_EVIDENCE"
        val action = AgentAction(
            id = "failed-build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentOnDeviceRuntimeTools.EXECUTE,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the phone project",
            result = "Build failed",
            evidence = marker,
            requiresConfirmation = false
        )
        val request = request("Fix the Android build on this phone").copy(
            executionHistory = listOf(action)
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            request = request,
            failedAction = action,
            reason = "The build tool returned a failure"
        )

        assertEquals(1, prompt.split(marker).size - 1)
        assertTrue(prompt.contains("The last phone action failed"))
        assertTrue(prompt.contains("The build tool returned a failure"))
    }

    @Test
    fun `recovery prompt embeds failure evidence when no progress ledger exists`() {
        val marker = "STANDALONE_RUNTIME_FAILURE_EVIDENCE"
        val action = AgentAction(
            id = "standalone-failure",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentOnDeviceRuntimeTools.EXECUTE,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the phone project",
            evidence = marker,
            requiresConfirmation = false
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            request = request("Fix the Android build on this phone"),
            failedAction = action,
            reason = "The build tool returned a failure"
        )

        assertTrue(prompt.contains(marker))
        assertTrue(prompt.contains("Failed action:"))
    }

    @Test
    fun `continuation uses a smaller equivalent contract without dropping phone boundaries`() {
        val request = request("Improve SignalASI on this phone and submit a pull request")
        val planning = AgentSupervisedProjectLoop.planningPrompt(request)
        val continuation = AgentSupervisedProjectLoop.continuationPrompt(request)

        assertTrue(continuation.length < planning.length)
        assertTrue(planning.substringBefore("Available phone tools:").length < 4_800)
        assertTrue(continuation.contains("execution_location is always phone"))
        assertTrue(continuation.contains("one action, or 2-4 independent read-only"))
        assertTrue(continuation.contains("Set completes_goal=true only when"))
        assertTrue(continuation.contains("signalasi.project.repository.* for all Git operations"))
        assertTrue(continuation.contains("never run Git through signalasi.runtime.execute"))
        assertTrue(continuation.contains("verification_kind and no source"))
        assertTrue(continuation.contains("project_profiles"))
        assertTrue(continuation.contains("required executables"))
        assertTrue(continuation.contains("feature branch, tests, commit, push, and pull-request URL"))
        assertTrue(continuation.contains("Available phone tools"))
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            request.executionHistory
        )
        val manifest = continuation
            .substringAfter("Available phone tools:\n")
            .substringBefore(AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER)
        assertTrue(request.runtimeContext.nativeTools
            .filter { descriptor ->
                request.runtimeContext.isNativeToolExecutable(descriptor.id) &&
                    AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(descriptor.id) &&
                    descriptor.id !in blocked
            }
            .map(AgentNativeToolDescriptor::id)
            .all(manifest::contains))
        assertTrue(blocked.none(manifest::contains))
    }

    @Test
    fun `stable contract and tool inventory form a reusable prompt cache prefix`() {
        val first = AgentSupervisedProjectLoop.planningPrompt(
            request("Fix the Android build and submit a pull request")
        )
        val second = AgentSupervisedProjectLoop.planningPrompt(
            request("Update the documentation and submit a pull request")
        )
        val boundary = AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER

        assertTrue(first.indexOf("Available phone tools:") < first.indexOf(boundary))
        assertTrue(first.indexOf(boundary) < first.indexOf("User goal:"))
        assertEquals(first.substringBefore(boundary), second.substringBefore(boundary))
        assertTrue(first.substringAfter(boundary).contains("Fix the Android build"))
        assertTrue(second.substringAfter(boundary).contains("Update the documentation"))
    }

    @Test
    fun `equivalent supervised project requests reuse their complete base prompt`() {
        val firstRequest = request("Build and verify the Android project")
        val equivalentRequest = firstRequest.copy(
            runtimeContext = firstRequest.runtimeContext.copy()
        )

        val first = AgentSupervisedProjectLoop.continuationPrompt(firstRequest)
        val second = AgentSupervisedProjectLoop.continuationPrompt(equivalentRequest)

        assertSame(first, second)
    }

    @Test
    fun `new verified project observation invalidates the complete base prompt`() {
        val base = request("Build and verify the Android project")
        val completed = AgentAction(
            id = "build-observation",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentOnDeviceRuntimeTools.EXECUTE,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Run project tests",
            result = "Tests passed",
            evidence = "Tests passed",
            requiresConfirmation = false
        )

        val first = AgentSupervisedProjectLoop.continuationPrompt(base)
        val second = AgentSupervisedProjectLoop.continuationPrompt(
            base.copy(executionHistory = listOf(completed))
        )

        assertNotSame(first, second)
        assertTrue(second.contains("Tests passed"))
    }

    @Test
    fun `current user goal appears once in the supervised project prompt`() {
        val goal = "Update the Android project and submit a pull request"
        val base = request(goal)
        val withCurrentTurn = base.copy(
            conversationContext = AgentConversationContext(
                conversationId = "deduplicated-project-goal",
                summary = "Keep the existing architecture",
                turns = listOf(
                    AgentTranscriptEntry(
                        id = "current-user-turn",
                        role = AgentTranscriptRole.USER,
                        text = goal,
                        timestampMillis = 1L,
                        conversationId = "deduplicated-project-goal",
                        turnId = "turn-current"
                    )
                ),
                privateMode = false
            )
        )

        val prompt = AgentSupervisedProjectLoop.planningPrompt(withCurrentTurn)

        assertEquals(1, prompt.split(goal).size - 1)
        assertTrue(prompt.contains("Keep the existing architecture"))
    }

    @Test
    fun `long project goal preserves its objective and final acceptance criteria`() {
        val opening = "Update the SignalASI Android project on the phone."
        val finalAcceptance = "FINAL_ACCEPTANCE: publish a verified pull request URL."
        val goal = buildString {
            append(opening)
            repeat(600) {
                append(" Inspect evidence before each implementation decision and preserve existing behavior.")
            }
            append(' ').append(finalAcceptance)
        }

        val prompt = AgentSupervisedProjectLoop.planningPrompt(request(goal))

        assertTrue(goal.length > 8_000)
        assertTrue(prompt.contains(opening))
        assertTrue(prompt.contains("[middle omitted]"))
        assertTrue(prompt.contains(finalAcceptance))
        assertTrue(prompt.length <= 24_000)
    }

    @Test
    fun `supervised project prompts stay within explicit control plane budgets`() {
        val request = request("Improve SignalASI on this phone and submit a pull request")
        val planning = AgentSupervisedProjectLoop.planningPrompt(request)
        val continuation = AgentSupervisedProjectLoop.continuationPrompt(request)
        val boundary = AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER
        val toolsHeader = "Available phone tools:\n"
        val planningContractLength = planning.substringBefore(toolsHeader).length
        val planningToolLength = planning.substringAfter(toolsHeader).substringBefore(boundary).length
        val continuationContractLength = continuation.substringBefore(toolsHeader).length
        val continuationToolLength = continuation.substringAfter(toolsHeader).substringBefore(boundary).length

        assertTrue("Planning contract expanded to $planningContractLength characters", planningContractLength <= 5_800)
        assertTrue("Continuation contract expanded to $continuationContractLength characters", continuationContractLength <= 3_000)
        assertEquals(planningToolLength, continuationToolLength)
        assertTrue(planning.length <= 24_000)
        assertTrue(continuation.length <= 24_000)
    }

    @Test
    fun `project loop prompt excludes unrelated memory and knowledge payloads`() {
        val base = request("Fix the current phone project")
        val marker = "UNRELATED_PRIVATE_CONTEXT_MARKER"
        val enriched = base.copy(
            memories = listOf(
                AgentMemoryItem(
                    kind = AgentMemoryKind.PREFERENCE,
                    value = marker
                )
            ),
            runtimeContext = base.runtimeContext.copy(
                memories = listOf(
                    AgentMemoryItem(
                        kind = AgentMemoryKind.PREFERENCE,
                        value = marker
                    )
                ),
                knowledgeItems = listOf(
                    AgentKnowledgeItem(
                        kind = AgentKnowledgeKind.DOCUMENT,
                        title = marker,
                        content = marker
                    )
                ),
                knowledgeStats = AgentKnowledgeStats(itemCount = 1, sourceCount = 1)
            )
        )

        val prompt = AgentSupervisedProjectLoop.continuationPrompt(enriched)

        assertFalse(prompt.contains(marker))
        assertTrue(prompt.contains("Fix the current phone project"))
        assertTrue(prompt.contains("Available phone tools"))
    }

    @Test
    fun `stalled action remains unknown until the model verifies its outcome`() {
        val action = AgentAction(
            id = "build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentOnDeviceRuntimeTools.EXECUTE,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the phone project",
            result = "The task stopped reporting progress",
            evidence = """{"outcome_state":"unknown","watchdog_reason":"running_progress_timeout"}""",
            requiresConfirmation = false
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            request = request("Continue the Android project on this phone"),
            failedAction = action,
            reason = "running_progress_timeout"
        )

        assertTrue(prompt.contains("outcome is unknown rather than proven failed"))
        assertTrue(prompt.contains("Inspect durable receipts, repository state, artifacts, or process state"))
        assertTrue(prompt.contains("Action with unknown outcome"))
        assertFalse(prompt.contains("The last phone action failed"))
    }

    @Test
    fun `auto model continuation receives recent sanitized phone tool observations`() {
        val failed = AgentAction(
            id = "clone",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentMobileProjectNativeTools.CLONE,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Prepare the phone repository",
            result = "Git failed with exit code 128; access_token=top-secret",
            evidence = "repository_state=partial; branch=feature/unborn",
            requiresConfirmation = false
        )

        val prompt = AgentSupervisedProjectLoop.continuationPrompt(
            request("Continue the phone project").copy(executionHistory = listOf(failed))
        )

        assertTrue(prompt.contains("SignalASI-owned context"))
        assertTrue(prompt.contains("Git failed with exit code 128"))
        assertTrue(prompt.contains("repository_state=partial"))
        assertFalse(prompt.contains("top-secret"))
        assertTrue(prompt.contains("access_token=[redacted]"))
    }

    @Test
    fun `project loop installs evidence backed dependencies and retries the blocked step`() {
        val prompt = AgentSupervisedProjectLoop.planningPrompt(
            request("Clone the project on this phone, build it, and fix any failures")
        )

        assertTrue(prompt.contains("Debian apt/dpkg as root"))
        assertTrue(prompt.contains("project_profiles"))
        assertTrue(prompt.contains("reuse them instead of listing directories or rereading manifests"))
        assertTrue(prompt.contains("retry the exact blocked step"))
        assertTrue(prompt.contains("Package installation alone is never completion evidence"))
        assertTrue(prompt.contains("direct network access for apt, Git, curl/wget"))
        assertTrue(prompt.contains("Never create, repair, or imitate .git metadata manually"))
        assertTrue(prompt.contains("Never invoke Git through signalasi.runtime.execute"))
        assertTrue(prompt.contains("installs Git, CA certificates, and the SSH client"))
        assertTrue(prompt.contains("GitHub pull request URL"))
        assertTrue(prompt.contains("partial means Git metadata exists but HEAD is not usable"))
        assertTrue(prompt.contains("prepares empty, ready, or partial state"))
        assertTrue(prompt.contains("FETCH_HEAD is a valid base_ref"))
        assertTrue(prompt.contains(AgentMobileProjectArchiveTools.IMPORT_PROJECT))
        assertTrue(prompt.contains(AgentMobileProjectArchiveTools.IMPORT_GRADLE_CACHE))
        assertTrue(prompt.contains("/root and /workspace are phone Linux guest paths"))
        assertTrue(prompt.contains("working directory set to the current isolated phone project"))
        assertTrue(prompt.contains("never cd to /workspace"))
        assertTrue(prompt.contains("documentation-only change"))
        assertTrue(prompt.contains("repository.diff inspection is sufficient verification"))
        assertTrue(AgentMobileProjectArchiveTools.toolIds.all(AgentPhoneNativeToolCatalog.defaultToolIds::contains))
    }

    @Test
    fun `empty workspace remains an observation for the model instead of a forced clone`() {
        val raw = """
            {"execution_location":"phone","summary":"Inspect the workspace first.","actions":[
              {"ref":"inspect","kind":"CALL_NATIVE_TOOL","target":"signalasi.project.repository.inspect",
               "description":"Inspect repository","depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.project.repository.inspect","arguments":{"workspace_id":"current"}}}
            ]}
        """.trimIndent()

        assertEquals(raw, AgentSupervisedProjectControlPayload.normalize(raw))
    }

    @Test
    fun `single action iteration removes stale dependencies from earlier rounds`() {
        val raw = """
            {"execution_location":"phone","summary":"Create the feature branch.","actions":[
              {"ref":"branch","kind":"CALL_NATIVE_TOOL","target":"signalasi.project.repository.branch.checkout",
               "description":"Create the feature branch","depends_on":["pull_latest"],"use_outputs_from":["pull_latest"],
               "parameters":{"tool_id":"signalasi.project.repository.branch.checkout","arguments":{
                 "workspace_id":"current","branch":"feature/test","create":true
               }}}
            ]}
        """.trimIndent()

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
            .getJSONArray("actions")
            .getJSONObject(0)

        assertEquals(0, normalized.getJSONArray("depends_on").length())
        assertEquals(0, normalized.getJSONArray("use_outputs_from").length())
    }

    @Test
    fun `continuation prompt retains repository evidence from the conversation`() {
        val base = request("继续")
        val context = AgentConversationContext(
            conversationId = "prompt-test",
            summary = "",
            turns = listOf(
                AgentTranscriptEntry(
                    id = "user-1",
                    role = AgentTranscriptRole.USER,
                    text = "开发 https://github.com/signalasi/SignalASI，测试并提交 PR",
                    timestampMillis = 1L,
                    conversationId = "prompt-test",
                    turnId = "turn-1"
                )
            ),
            privateMode = false
        )
        val prompt = AgentSupervisedProjectLoop.continuationPrompt(base.copy(conversationContext = context))

        assertTrue(prompt.contains("Durable project context"))
        assertTrue(prompt.contains("https://github.com/signalasi/SignalASI"))
        assertTrue(prompt.contains("Use the current conversation workspace only"))
        assertTrue(prompt.contains("A new conversation intentionally starts with an empty isolated workspace"))
    }

    @Test
    fun `project tools are ordered ahead of generic runtime tools`() {
        fun descriptor(id: String) = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = id,
            description = id,
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            outputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            risk = AgentNativeToolRisk.LOW
        )
        val ordered = AgentSupervisedProjectToolInventory.ordered(
            listOf(
                descriptor("signalasi.runtime.execute"),
                descriptor("signalasi.workspace.file.read"),
                descriptor(AgentMobileProjectNativeTools.CLONE),
                descriptor(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST)
            )
        ).map(AgentNativeToolDescriptor::id)

        assertEquals(AgentMobileProjectNativeTools.CLONE, ordered[0])
        assertEquals(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST, ordered[1])
        assertEquals("signalasi.workspace.file.read", ordered[2])
        assertEquals("signalasi.runtime.execute", ordered[3])
    }

    @Test
    fun `project tool manifest is reused within the same runtime catalog`() {
        val context = projectToolContext()

        val first = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)
        val second = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)

        assertSame(first, second)
    }

    @Test
    fun `project tool manifest falls back to descriptor availability without a capability snapshot`() {
        val available = projectToolDescriptor(AgentMobileProjectNativeTools.CLONE)
        val unavailable = projectToolDescriptor(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST).copy(
            availability = AgentNativeToolAvailability(
                AgentNativeToolAvailabilityStatus.UNAVAILABLE,
                "Runtime unavailable"
            )
        )
        val context = request("Inspect the phone project").runtimeContext.copy(
            nativeTools = listOf(available, unavailable),
            capabilityMatrix = AgentRuntimeCapabilitySnapshot.EMPTY
        )

        val manifest = AgentSupervisedProjectToolInventory.render(
            context,
            maximumSchemaCharacters = 240
        )

        assertTrue(manifest.contains("- ${available.id} |"))
        assertFalse(manifest.contains("- ${unavailable.id} |"))
    }

    @Test
    fun `initial lifecycle working set reduces schemas without hiding implementation tools`() {
        val toolIds = AgentMobileProjectNativeTools.toolIds + setOf(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH,
            AgentOnDeviceRuntimeTools.EXECUTE
        )
        val tools = toolIds.map(::projectToolDescriptor)
        val base = request("Improve the phone project").runtimeContext
        val context = base.copy(
            nativeTools = tools,
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = tools,
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(emptyList())

        val full = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)
        val focused = AgentSupervisedProjectToolInventory.render(
            context = context,
            maximumSchemaCharacters = 240,
            temporarilyBlockedToolIds = blocked
        )

        assertEquals(toolIds.size, full.lineSequence().count(String::isNotBlank))
        assertEquals(toolIds.size - 5, focused.lineSequence().count(String::isNotBlank))
        assertTrue(focused.length * 5 <= full.length * 4)
        assertTrue(focused.contains("- ${AgentMobileProjectNativeTools.CLONE} |"))
        assertTrue(focused.contains("- ${AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT} |"))
        assertTrue(focused.contains("- ${AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH} |"))
        assertTrue(focused.contains("- ${AgentOnDeviceRuntimeTools.EXECUTE} |"))
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.COMMIT} |"))
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.PUSH} |"))
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.CREATE_PULL_REQUEST} |"))
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST} |"))
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST} |"))
    }

    @Test
    fun `phase manifest compacts inactive schemas without hiding tools`() {
        fun descriptor(index: Int): AgentNativeToolDescriptor = AgentNativeToolDescriptor(
            id = "signalasi.workspace.synthetic.tool$index",
            version = "1.0.0",
            title = "Synthetic tool $index",
            description = "Synthetic project tool",
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = linkedMapOf(
                    "workspace_id" to AgentNativeJsonSchema.string(),
                    "path" to AgentNativeJsonSchema.string(),
                    "expected_text" to AgentNativeJsonSchema.string(),
                    "replacement_text" to AgentNativeJsonSchema.string(),
                    "start_line" to AgentNativeJsonSchema.integer(),
                    "max_lines" to AgentNativeJsonSchema.integer()
                ),
                required = setOf("workspace_id", "path", "expected_text", "replacement_text")
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            risk = AgentNativeToolRisk.LOW
        )
        val tools = (0 until 48).map(::descriptor)
        val base = request("Improve the phone project").runtimeContext
        val context = base.copy(
            nativeTools = tools,
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = tools,
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
        val detailedIds = tools.take(8).mapTo(linkedSetOf(), AgentNativeToolDescriptor::id)

        val full = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)
        val compact = AgentSupervisedProjectToolInventory.render(
            context = context,
            maximumSchemaCharacters = 240,
            detailedToolIds = detailedIds
        )

        tools.forEach { tool -> assertTrue(compact.contains("- ${tool.id} |")) }
        assertTrue(
            "Expected at least 20% manifest reduction, full=${full.length}, compact=${compact.length}",
            compact.length * 5 <= full.length * 4
        )
        assertTrue(compact.contains("replacement_text!:string"))
    }

    @Test
    fun `connector status changes reuse the project tool manifest`() {
        val context = projectToolContext()
        val connectorChanged = context.copy(
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = context.nativeTools,
                systemTools = context.systemTools,
                targets = supervisedTargets().take(1)
            )
        )

        val first = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)
        val second = AgentSupervisedProjectToolInventory.render(connectorChanged, maximumSchemaCharacters = 240)

        assertSame(first, second)
    }

    @Test
    fun `native availability changes rebuild the project tool manifest`() {
        val context = projectToolContext()
        val removedTool = context.nativeTools.first { tool ->
            context.isNativeToolExecutable(tool.id) &&
                AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(tool.id)
        }
        val changed = context.copy(
            capabilityMatrix = context.capabilityMatrix.copy(
                entries = context.capabilityMatrix.entries.map { entry ->
                    if (entry.source == AgentRuntimeCapabilitySource.NATIVE_TOOL && entry.id == removedTool.id) {
                        entry.copy(state = AgentRuntimeCapabilityState.UNAVAILABLE)
                    } else {
                        entry
                    }
                }
            )
        )

        val first = AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 240)
        val second = AgentSupervisedProjectToolInventory.render(changed, maximumSchemaCharacters = 240)

        assertNotSame(first, second)
        assertTrue(first.contains("- ${removedTool.id} |"))
        assertFalse(second.contains("- ${removedTool.id} |"))
    }

    @Test
    fun `concurrent project tool manifest compilation converges on one cached value`() {
        val context = projectToolContext()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                AgentSupervisedProjectToolInventory.render(context, maximumSchemaCharacters = 917)
            }
        }
        start.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    @Test
    fun `concurrent project prompt prefix compilation converges on one cached value`() {
        val context = projectToolContext()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                AgentSupervisedProjectPromptTemplate.render(
                    context = context,
                    evidenceExpected = true,
                    maximumSchemaCharacters = 919
                )
            }
        }
        start.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    @Test
    fun `generic runtime cannot execute project Git commands`() {
        val rawGitAction = """
            {"execution_location":"phone","summary":"Inspect Git.","actions":[
              {"ref":"inspect","kind":"CALL_NATIVE_TOOL","target":"signalasi.runtime.execute",
               "description":"Inspect repository","depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"signalasi.runtime.execute","arguments":{
                 "workspace_id":"current","language":"shell","source":"git status --short"
               }}}
            ]}
        """.trimIndent()
        val ordinaryShellAction = rawGitAction.replace("git status --short", "./gradlew test")
        val multilineGitAction = rawGitAction.replace(
            "git status --short",
            "set -eu\\ngit fetch origin main\\ngit status --short"
        )
        val timeoutGitAction = rawGitAction.replace(
            "git status --short",
            "set -eu\\ntimeout 30s git switch -c feature/test"
        )

        assertTrue(AgentSupervisedRepositoryPolicy.violatesProjectGitBoundary(rawGitAction))
        assertTrue(AgentSupervisedRepositoryPolicy.violatesProjectGitBoundary(multilineGitAction))
        assertTrue(AgentSupervisedRepositoryPolicy.violatesProjectGitBoundary(timeoutGitAction))
        assertFalse(AgentSupervisedRepositoryPolicy.violatesProjectGitBoundary(ordinaryShellAction))
    }

    @Test
    fun `visible fallback summary follows the user goal language`() {
        val chineseRequest = request("\u5728\u624b\u673a\u4e0a\u4fee\u590d\u8fd9\u4e2a\u9879\u76ee\u5e76\u8fd0\u884c\u6d4b\u8bd5")
        val englishRequest = request("Fix this project on the phone and run its tests")

        assertEquals(
            "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\uff0c\u5df2\u8981\u6c42\u5b83\u4fee\u6b63\u8ba1\u5212\u7ed3\u6784\u540e\u7ee7\u7eed\u3002",
            AgentSupervisedProjectLoop.visibleSummary(
                chineseRequest,
                english = "The model response was not executable.",
                chinese = "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\uff0c\u5df2\u8981\u6c42\u5b83\u4fee\u6b63\u8ba1\u5212\u7ed3\u6784\u540e\u7ee7\u7eed\u3002"
            )
        )
        assertEquals(
            "The model response was not executable.",
            AgentSupervisedProjectLoop.visibleSummary(
                englishRequest,
                english = "The model response was not executable.",
                chinese = "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\u3002"
            )
        )
    }

    @Test
    fun `every structured model round exposes its public summary`() {
        val response = """
            {"execution_location":"phone","summary":"Inspected the runtime and selected the next verified step.","actions":[]}
        """.trimIndent()

        assertEquals(
            "Inspected the runtime and selected the next verified step.",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    @Test
    fun `invalid model round remains visible without private reasoning`() {
        val response = """
            <think>private chain of thought</think>
            The runtime check failed, so I will inspect the installed packs next.
        """.trimIndent()

        assertEquals(
            "The runtime check failed, so I will inspect the installed packs next.",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    @Test
    fun `structured round without summary exposes bounded action descriptions`() {
        val response = """
            {"execution_location":"phone","actions":[
              {"description":"Inspect the phone runtime"},
              {"description":"Run the verified program"}
            ]}
        """.trimIndent()

        assertEquals(
            "- Inspect the phone runtime\n- Run the verified program",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    @Test
    fun `format repair preserves correction after a full provider neutral context`() {
        val invalidTool = "signalasi.project.repository.state"
        val request = request("Continue this phone project").copy(
            conversationContext = AgentConversationContext(
                conversationId = "auto-context",
                summary = "Earlier provider summary. ".repeat(600),
                turns = listOf(
                    AgentTranscriptEntry(
                        id = "older-assistant-turn",
                        role = AgentTranscriptRole.ASSISTANT,
                        text = "Earlier assistant inference. ".repeat(300),
                        timestampMillis = 1L
                    )
                ),
                privateMode = false
            )
        )

        val prompt = AgentSupervisedProjectLoop.formatRepairPrompt(
            request,
            "{\"actions\":[{\"parameters\":{\"tool_id\":\"$invalidTool\"}}]}"
        )

        assertTrue(prompt.contains("not a valid executable ActionPlan"))
        assertTrue(prompt.contains(invalidTool))
        assertTrue(prompt.contains("Available phone tools"))
        assertTrue(prompt.contains("newest verified tool observation overrides"))
    }

    @Test
    fun `auto provider context keeps the durable summary and newest complete turn`() {
        val conversationId = "auto-provider-context"
        val latestMarker = "LATEST_USER_CONSTRAINT_MUST_SURVIVE"
        val oldTurns = (1..18).flatMap { index ->
            listOf(
                AgentTranscriptEntry(
                    id = "user-$index",
                    role = AgentTranscriptRole.USER,
                    text = "Older request $index " + "context ".repeat(180),
                    timestampMillis = index.toLong(),
                    conversationId = conversationId,
                    turnId = "turn-$index"
                ),
                AgentTranscriptEntry(
                    id = "assistant-$index",
                    role = AgentTranscriptRole.ASSISTANT,
                    text = "Older response $index " + "evidence ".repeat(180),
                    timestampMillis = index.toLong(),
                    conversationId = conversationId,
                    turnId = "turn-$index"
                )
            )
        }
        val latest = AgentTranscriptEntry(
            id = "latest-user",
            role = AgentTranscriptRole.USER,
            text = latestMarker,
            timestampMillis = 100L,
            conversationId = conversationId,
            turnId = "latest-turn"
        )
        val prompt = AgentSupervisedProjectLoop.continuationPrompt(
            request("Continue the phone project").copy(
                conversationContext = AgentConversationContext(
                    conversationId = conversationId,
                    summary = "Durable cross-provider project summary",
                    turns = oldTurns + latest,
                    privateMode = false
                )
            )
        )

        assertTrue(prompt.contains("Durable cross-provider project summary"))
        assertTrue(prompt.contains(latestMarker))
        assertTrue(prompt.contains(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_HEADER))
        assertTrue(prompt.length <= 24_000)
    }

    @Test
    fun `supervised project context keeps earlier constraints beyond four recent turns`() {
        val conversationId = "project-history"
        val originalConstraint = "EARLY_PROJECT_CONSTRAINT_KEEP_ANDROID_EXECUTION"
        val turns = buildList {
            add(
                AgentTranscriptEntry(
                    id = "initial-user",
                    role = AgentTranscriptRole.USER,
                    text = originalConstraint,
                    timestampMillis = 1L,
                    conversationId = conversationId,
                    turnId = "turn-1"
                )
            )
            (2..8).forEach { index ->
                add(
                    AgentTranscriptEntry(
                        id = "assistant-$index",
                        role = AgentTranscriptRole.ASSISTANT,
                        text = "Verified project observation $index",
                        timestampMillis = index.toLong(),
                        conversationId = conversationId,
                        turnId = "turn-$index"
                    )
                )
            }
        }

        val prompt = AgentSupervisedProjectLoop.continuationPrompt(
            request("Continue from the verified project state").copy(
                conversationContext = AgentConversationContext(
                    conversationId = conversationId,
                    summary = "",
                    turns = turns,
                    privateMode = false
                )
            )
        )

        assertTrue(prompt.contains(originalConstraint))
        assertTrue(prompt.contains("Verified project observation 8"))
        assertTrue(prompt.length <= 24_000)
    }

    @Test
    fun `large continuation keeps every executable phone tool and newest evidence`() {
        val tools = largeProjectToolCatalog()
        val history = (1..20).map { index ->
            AgentAction(
                id = "history-$index",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = tools[index % tools.size].id,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.COMPLETED,
                description = "Historical project action $index " + "detail ".repeat(80),
                result = "Historical observation $index " + "evidence ".repeat(120),
                evidence = if (index == 20) "LATEST_VERIFIED_PHONE_EVIDENCE" else "evidence-$index",
                requiresConfirmation = false
            )
        }
        val base = request("Improve the phone project and verify the result")
        val prompt = AgentSupervisedProjectLoop.continuationPrompt(
            base.copy(
                runtimeContext = base.runtimeContext.copy(
                    nativeTools = tools,
                    capabilityMatrix = AgentRuntimeCapabilitySnapshot.EMPTY
                ),
                conversationContext = AgentConversationContext(
                    conversationId = "large-prompt",
                    summary = "Durable summary " + "context ".repeat(800),
                    turns = listOf(
                        AgentTranscriptEntry(
                            id = "latest-user",
                            role = AgentTranscriptRole.USER,
                            text = "LATEST_USER_PROJECT_CONSTRAINT",
                            timestampMillis = 2L,
                            conversationId = "large-prompt",
                            turnId = "latest-turn"
                        )
                    ),
                    privateMode = false
                ),
                executionHistory = history
            )
        )

        val missingToolIds = tools.map(AgentNativeToolDescriptor::id).filterNot(prompt::contains)
        assertTrue(prompt.length <= 24_000)
        assertTrue("Missing tools: $missingToolIds; promptLength=${prompt.length}", missingToolIds.isEmpty())
        assertTrue(prompt.contains("LATEST_USER_PROJECT_CONSTRAINT"))
        assertTrue(prompt.contains("LATEST_VERIFIED_PHONE_EVIDENCE"))
        assertEquals(1, prompt.split("LATEST_VERIFIED_PHONE_EVIDENCE").size - 1)
        assertFalse(prompt.contains("deliberately verbose project tool description"))
        assertTrue(prompt.contains("workspace_id!:string"))
        assertTrue(prompt.contains("mode:string(inspect|modify|verify)"))
    }

    @Test
    fun `large recovery keeps latest failure reason and evidence after tool inventory compaction`() {
        val tools = largeProjectToolCatalog()
        val failed = AgentAction(
            id = "failed-build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = tools.first().id,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the Android project",
            result = "build output " + "detail ".repeat(900),
            evidence = "LATEST_FAILED_PHONE_TOOL_EVIDENCE",
            requiresConfirmation = false
        )
        val base = request("Fix the phone project and verify it")
        val expanded = base.copy(
            runtimeContext = base.runtimeContext.copy(
                nativeTools = tools,
                capabilityMatrix = AgentRuntimeCapabilitySnapshot.EMPTY
            ),
            conversationContext = AgentConversationContext(
                conversationId = "large-recovery",
                summary = "Historical project context ".repeat(600),
                turns = emptyList(),
                privateMode = false
            ),
            executionHistory = listOf(failed)
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            expanded,
            failed,
            "LATEST_FAILURE_REASON_FROM_WATCHDOG"
        )

        val missingToolIds = tools.map(AgentNativeToolDescriptor::id).filterNot(prompt::contains)
        assertTrue(prompt.length <= 24_000)
        assertTrue("Missing tools: $missingToolIds; promptLength=${prompt.length}", missingToolIds.isEmpty())
        assertTrue(prompt.contains("LATEST_FAILURE_REASON_FROM_WATCHDOG"))
        assertTrue(prompt.contains("LATEST_FAILED_PHONE_TOOL_EVIDENCE"))
    }

    @Test
    fun `large progress repair keeps rejection reason and response after tool inventory compaction`() {
        val tools = largeProjectToolCatalog()
        val base = request("Continue the phone project without repeating verified work")
        val expanded = base.copy(
            runtimeContext = base.runtimeContext.copy(
                nativeTools = tools,
                capabilityMatrix = AgentRuntimeCapabilitySnapshot.EMPTY
            ),
            conversationContext = AgentConversationContext(
                conversationId = "large-progress-repair",
                summary = "Historical project context ".repeat(600),
                turns = emptyList(),
                privateMode = false
            )
        )

        val prompt = AgentSupervisedProjectLoop.progressRepairPrompt(
            request = expanded,
            response = "LATEST_REJECTED_MODEL_ACTION_RESPONSE",
            violation = "LATEST_PROGRESS_VIOLATION_REASON"
        )

        val missingToolIds = tools.map(AgentNativeToolDescriptor::id).filterNot(prompt::contains)
        assertTrue(prompt.length <= 24_000)
        assertTrue("Missing tools: $missingToolIds; promptLength=${prompt.length}", missingToolIds.isEmpty())
        assertTrue(prompt.contains("LATEST_PROGRESS_VIOLATION_REASON"))
        assertTrue(prompt.contains("LATEST_REJECTED_MODEL_ACTION_RESPONSE"))
    }

    private fun largeProjectToolCatalog(): List<AgentNativeToolDescriptor> = (1..64).map { index ->
        AgentNativeToolDescriptor(
            id = "signalasi.project.test.tool.${index.toString().padStart(2, '0')}",
            version = "1.0.0",
            title = "Project tool $index",
            description = "A deliberately verbose project tool description ".repeat(20),
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf(
                    "workspace_id" to AgentNativeJsonSchema.string(description = "Workspace identifier".repeat(20)),
                    "path" to AgentNativeJsonSchema.string(description = "Project relative path".repeat(20)),
                    "mode" to AgentNativeJsonSchema.string(enumValues = listOf("inspect", "modify", "verify")),
                    "recursive" to AgentNativeJsonSchema.boolean()
                ),
                required = setOf("workspace_id", "path"),
                additionalProperties = false
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW
        )
    }

    private fun supervisedConnector(
        connectorId: String,
        fallbackIds: String,
        manuallyLocked: Boolean = false
    ): AgentAction = AgentAction(
        id = "supervised-connector",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = "Codex",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.WAITING_RESPONSE,
        description = "Supervise phone project",
        parameters = mapOf(
            "connector_id" to connectorId,
            "connector_kind" to "agent",
            "connector_adapter_type" to "stale-adapter",
            "connector_failure_domain" to "stale-domain",
            "routing_fallback_ids" to fallbackIds,
            "manual_target_locked" to manuallyLocked.toString()
        ),
        requiresConfirmation = false
    )

    private fun supervisedTargets(): List<AgentCallableTarget> = listOf(
        AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE),
            failureDomain = "desktop-codex",
            adapterType = "codex-app-server-or-cli"
        ),
        AgentCallableTarget(
            id = "cloud-models",
            title = "Cloud Models",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING),
            failureDomain = "cloud-provider",
            adapterType = "cloud-model-api"
        ),
        AgentCallableTarget(
            id = "hermes",
            title = "Hermes",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.DISCONNECTED,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.RESEARCH),
            failureDomain = "desktop-hermes",
            adapterType = "hermes-cli"
        )
    )

    private fun request(goal: String): AgentRequest {
        val screen = ScreenContext(
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
        )
        return AgentRequest(
            goal = goal,
            screen = screen,
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "prompt-test",
                goal = goal,
                screen = screen,
                permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList()
            )
        )
    }

    private fun projectToolContext(): AgentRuntimeContext {
        val tools = listOf(
            projectToolDescriptor(AgentMobileProjectNativeTools.CLONE),
            projectToolDescriptor(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST)
        )
        val base = request("Improve the phone project").runtimeContext
        return base.copy(
            nativeTools = tools,
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = tools,
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
    }

    private fun projectToolDescriptor(id: String): AgentNativeToolDescriptor = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = id,
        description = "Project test tool",
        location = AgentNativeToolLocation.PHONE,
        inputSchema = AgentNativeJsonSchema.objectSchema(
            properties = mapOf("workspace_id" to AgentNativeJsonSchema.string())
        ),
        outputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
        risk = AgentNativeToolRisk.LOW
    )
}
