package com.galaxyssi.chat

import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSystemToolPlannerTest {
    @Test
    fun selectedCodexReasonsWhilePhoneLinuxExecutesTheRequestedCommand() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val runtime = nativeDescriptor(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "Execute in phone Linux",
            AgentNativeToolRisk.MEDIUM
        )
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(
                AgentCapability.CHAT,
                AgentCapability.CODE,
                AgentCapability.REASONING
            )
        )
        val goal = "Run node --version and npm --version in phone Linux and report both."
        val request = request(goal, screen, listOf(runtime), listOf(codex))
        val directConnector = AgentAction(
            id = "ask-codex",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask Codex",
            parameters = mapOf(
                "connector_id" to codex.id,
                "prompt" to goal,
                "manual_target_locked" to "true"
            ),
            requiresConfirmation = false
        )

        val plan = AgentPhoneReasoningProviderPlanner(directConnector).plan(request)
        val supervisor = plan.actions.single()

        assertEquals(PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE, plan.plannerProfile)
        assertTrue(supervisor.isSupervisedProjectConnector())
        assertEquals(codex.id, supervisor.parameters["connector_id"])
        assertEquals("true", supervisor.parameters["manual_target_locked"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, supervisor.parameters[INTERNAL_TASK_EXECUTION_MODE])
        assertTrue(supervisor.parameters.getValue("prompt").contains(goal))
        assertTrue(supervisor.parameters.getValue("prompt").contains(AgentOnDeviceRuntimeTools.EXECUTE))
        assertTrue(supervisor.parameters.getValue("prompt").contains("reasoning provider are independent"))
    }

    @Test
    fun repositoryTaskLetsTheModelChooseItsFirstEvidenceProducingTool() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val inspect = nativeDescriptor(
            AgentMobileProjectNativeTools.INSPECT,
            "Inspect phone repository",
            AgentNativeToolRisk.LOW
        )
        val request = request(
            goal = "Continue https://github.com/galaxyssi/GalaxySSI and create a PR",
            screen = screen,
            nativeTools = listOf(inspect)
        )
        val provider = AgentAction(
            id = "ask-model",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Cloud model",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask model",
            parameters = mapOf("connector_id" to "cloud"),
            requiresConfirmation = false
        )

        val plan = AgentPhoneReasoningProviderPlanner(provider).plan(request)

        val supervisor = plan.actions.single()
        assertTrue(supervisor.isSupervisedProjectConnector())
        assertEquals("", supervisor.parameters["depends_on"])
        assertEquals("", supervisor.parameters["use_outputs_from"])
        assertTrue(supervisor.parameters.getValue("prompt").contains(AgentMobileProjectNativeTools.INSPECT))
    }

    @Test
    fun resumedProjectLoopDoesNotRepeatAHostSelectedRepositoryPreflight() {
        val inspect = nativeDescriptor(
            AgentMobileProjectNativeTools.INSPECT,
            "Inspect phone repository",
            AgentNativeToolRisk.LOW
        )
        val request = request(
            goal = "Continue the current phone task",
            screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI"),
            nativeTools = listOf(inspect)
        )
        val provider = AgentAction(
            id = "ask-model",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Cloud model",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask model",
            parameters = mapOf("connector_id" to "cloud"),
            requiresConfirmation = false
        )

        val plan = AgentPhoneReasoningProviderPlanner(provider).plan(request)

        val supervisor = plan.actions.single()
        assertTrue(supervisor.isSupervisedProjectConnector())
        assertEquals("", supervisor.parameters["depends_on"])
        assertTrue(supervisor.parameters.getValue("prompt").contains(AgentMobileProjectNativeTools.INSPECT))
    }

    @Test
    fun selectedReasoningProviderDoesNotTurnOrdinaryConversationIntoPhoneExecution() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val request = request("hello", screen, emptyList())
        val directConnector = AgentAction(
            id = "ask-provider",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask Codex",
            parameters = mapOf("connector_id" to "codex", "prompt" to "hello"),
            requiresConfirmation = false
        )

        assertFalse(
            AgentPhoneAgentLoopRoutingPolicy.shouldUseSupervisedLoop(
                goal = request.goal,
                conversationContext = request.conversationContext,
                selectedAction = directConnector
            )
        )
    }

    @Test
    fun selectedReasoningProviderUsesPhoneExecutionForExecutableGoal() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val request = request("Write a Python program and verify it on this phone", screen, emptyList())
        val directConnector = AgentAction(
            id = "ask-provider",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask Codex",
            parameters = mapOf("connector_id" to "codex", "prompt" to request.goal),
            requiresConfirmation = false
        )

        assertTrue(
            AgentPhoneAgentLoopRoutingPolicy.shouldUseSupervisedLoop(
                goal = request.goal,
                conversationContext = request.conversationContext,
                selectedAction = directConnector
            )
        )
    }

    @Test
    fun connectorActionsCanNeverBypassThePhoneAgentReasoningLoop() {
        val connector = AgentAction(
            id = "connector",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Ask Codex",
            parameters = mapOf("connector_id" to "codex"),
            requiresConfirmation = false
        )
        val native = connector.copy(
            id = "native",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentOnDeviceRuntimeTools.STATUS,
            parameters = mapOf("tool_id" to AgentOnDeviceRuntimeTools.STATUS)
        )

        assertFalse(connector.canBypassAgentReasoningLoop())
        assertTrue(native.canBypassAgentReasoningLoop())
    }

    @Test
    fun normalizesCommonModelCompletionPayloadWithoutExposingControlJson() {
        val raw = """{"execution_location":"phone","summary":"Verified on the phone.","actions":[{"ref":"done","kind":"CALL_NATIVE_TOOL","target":"task-complete","depends_on":["write"],"use_outputs_from":["write"],"parameters":{"tool_id":"DRAFT_PLAN","arguments":{}}}]}"""

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw))
        val action = normalized.getJSONArray("actions").getJSONObject(0)

        assertTrue(AgentSupervisedProjectControlPayload.isControlPayload(raw))
        assertEquals(AgentActionKind.DRAFT_PLAN.name, action.getString("kind"))
        assertEquals("task-complete", action.getString("target"))
        assertEquals(0, action.getJSONArray("depends_on").length())
        assertEquals(0, action.getJSONArray("use_outputs_from").length())
        assertEquals(0, action.getJSONObject("parameters").length())
        assertEquals("Verified on the phone.", normalized.getString("summary"))
    }

    @Test
    fun completedPriorBatchReferencesAreRemovedFromTheCurrentExecutionGraph() {
        val completed = AgentAction(
            id = "sp2-2-write_python_source",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.COMPLETED,
            description = "Write Python source",
            parameters = mapOf("node_ref" to "write_python_source"),
            requiresConfirmation = false
        )
        val raw = """{"execution_location":"phone","actions":[{"ref":"verify_python_source","kind":"CALL_NATIVE_TOOL","target":"galaxyssi.workspace.file.read.text","depends_on":["write_python_source"],"use_outputs_from":["write_python_source"],"parameters":{"tool_id":"galaxyssi.workspace.file.read.text","arguments":{"workspace_id":"current","path":"sum.py"}}}]}"""

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw, listOf(completed)))
            .getJSONArray("actions")
            .getJSONObject(0)

        assertEquals(0, normalized.getJSONArray("depends_on").length())
        assertEquals(0, normalized.getJSONArray("use_outputs_from").length())
    }

    @Test
    fun currentBatchAndUnknownDependenciesRemainStrictlyValidated() {
        val completed = AgentAction(
            id = "sp1-1-old_step",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "tool",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Old step",
            parameters = mapOf("node_ref" to "old_step"),
            requiresConfirmation = false
        )
        val raw = """{"execution_location":"phone","actions":[{"ref":"write","kind":"CALL_NATIVE_TOOL","depends_on":[],"parameters":{}},{"ref":"verify","kind":"CALL_NATIVE_TOOL","depends_on":["write","unknown_step"],"parameters":{}}]}"""

        val normalized = JSONObject(AgentSupervisedProjectControlPayload.normalize(raw, listOf(completed)))
            .getJSONArray("actions")
            .getJSONObject(1)
            .getJSONArray("depends_on")

        assertEquals(listOf("write", "unknown_step"), (0 until normalized.length()).map(normalized::getString))
    }

    @Test
    fun supervisedProjectActionsKeepTheirBoundConversationAndTurn() {
        val modelAction = AgentAction(
            id = "write",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Write a project file",
            parameters = mapOf("input_json" to "{}")
        )
        val connector = AgentAction(
            id = "supervisor",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Plan phone project work",
            parameters = mapOf(
                INTERNAL_CONVERSATION_ID to "conversation-a",
                INTERNAL_TURN_ID to "turn-a",
                INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue
            )
        )

        val bound = modelAction.bindSupervisedProjectContext(connector)

        assertEquals("conversation-a", bound.parameters[INTERNAL_CONVERSATION_ID])
        assertEquals("turn-a", bound.parameters[INTERNAL_TURN_ID])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, bound.parameters[INTERNAL_TASK_EXECUTION_MODE])
        assertEquals("{}", bound.parameters["input_json"])
    }

    @Test
    fun handsStructuredPhoneToolEvidenceToTheSupervisingModel() {
        val inspect = AgentAction(
            id = "inspect",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = AgentMobileProjectNativeTools.INSPECT,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Inspect repository"
        )
        val reviewer = AgentAction(
            id = "review",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Review evidence",
            parameters = mapOf(
                "prompt" to "Decide whether the goal is complete",
                "use_outputs_from" to inspect.id
            )
        )
        val output = """{"branch":"main","head_commit":"abc123","clean":true}"""
        val plan = AgentPlanFactory.actions(
            request(
                "Inspect the phone repository",
                ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI"),
                emptyList(),
                emptyList()
            ),
            listOf(inspect, reviewer)
        ).markAction(
            inspect.id,
            AgentActionStatus.COMPLETED,
            AgentActionResult(
                actionId = inspect.id,
                success = true,
                message = "Phone project operation completed",
                metadata = mapOf("native_tool_output" to output)
            )
        )

        val materialized = plan.materializeToolInput(reviewer, allowOutputHandoff = true)

        assertTrue(materialized.parameters.getValue("prompt").contains(output))
        assertFalse(materialized.parameters.getValue("prompt").contains("Phone project operation completed"))
    }

    @Test
    fun preselectsReadOnlyCloudConversationWithoutFullModelPlanning() {
        val cloud = AgentCallableTarget(
            id = "cloud-models",
            title = "Cloud Models",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING)
        )
        val request = request(
            "Explain why the sky is blue",
            ScreenContext(foregroundApp = "", pageTitle = ""),
            emptyList(),
            listOf(cloud)
        )

        val action = RuleBasedAgentPlanner().directInformationConnectorAction(request)

        assertEquals(AgentActionKind.CALL_CONNECTOR, action?.kind)
        assertEquals("cloud-models", action?.parameters?.get("connector_id"))
    }

    @Test
    fun doesNotPreselectConnectorForPhoneDevelopmentTask() {
        val cloud = AgentCallableTarget(
            id = "cloud-models",
            title = "Cloud Models",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING, AgentCapability.CODE)
        )
        val request = request(
            "Write a Python program and verify it on this phone",
            ScreenContext(foregroundApp = "", pageTitle = ""),
            emptyList(),
            listOf(cloud)
        )

        assertEquals(null, RuleBasedAgentPlanner().directInformationConnectorAction(request))
    }

    @Test
    fun concretePhonePathOperationCannotBypassTheSupervisedPhoneLoop() {
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE, AgentCapability.REASONING)
        )
        val goal = "On this phone, create docs/model_reasoning_probe.txt, read it back, and verify it"
        val request = request(
            goal,
            ScreenContext(foregroundApp = "", pageTitle = ""),
            emptyList(),
            listOf(codex)
        )

        assertTrue(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal, request.conversationContext))
        assertEquals(null, RuleBasedAgentPlanner().directInformationConnectorAction(request))
        assertTrue(RuleBasedAgentPlanner().plan(request).isSupervisedProjectPlan())
    }

    @Test
    fun doesNotBypassThePhoneLoopForAProjectContinuation() {
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE, AgentCapability.REASONING)
        )
        val goal = "Create a branch in the current phone project, edit a file, then inspect the Git diff"
        val request = request(
            goal,
            ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI"),
            emptyList(),
            listOf(codex)
        )

        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(goal))
        assertEquals(null, RuleBasedAgentPlanner().directInformationConnectorAction(request))
    }

    @Test
    fun routesSmallChinesePythonWorkToThePhoneRuntime() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val runtime = nativeDescriptor(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "Execute in the on-device Linux sandbox",
            AgentNativeToolRisk.MEDIUM
        )
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE, AgentCapability.REASONING)
        )
        val plan = RuleBasedAgentPlanner().plan(
            request("\u8bf7\u5199\u4e00\u4e2a\u7b80\u5355\u7684python\u7a0b\u5e8f\uff0c\u5e76\u9a8c\u8bc1", screen, listOf(runtime), listOf(codex))
        )

        assertTrue(plan.validation.valid)
        assertEquals(listOf(AgentActionKind.CALL_CONNECTOR), plan.actions.map { it.kind })
        val supervisor = plan.actions.single()
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, supervisor.parameters["connector_task_mode"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, supervisor.parameters[INTERNAL_TASK_EXECUTION_MODE])
        assertTrue(supervisor.parameters["prompt"].orEmpty().contains("Always set execution_location to phone"))

        val generatedSource = "values = [1, 2, 3]\n    # preserve indentation and / characters\nprint(sum(values) / len(values))\nassert sum(values) == 6"
        val manifest = JSONObject()
            .put("schema", "galaxyssi.phone-development-manifest.v1")
            .put("language", "python")
            .put("file_name", "simple_average.py")
            .put("source", generatedSource)
            .put("artifact_paths", emptyList<String>())
            .toString()
        val author = AgentAction(
            id = "legacy-author",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Prepare code",
            parameters = mapOf("connector_task_mode" to PHONE_DEVELOPMENT_CONNECTOR_MODE)
        )
        val execute = AgentAction(
            id = "legacy-execute",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone Linux",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Run and verify",
            parameters = mapOf(
                "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE,
                "depends_on" to author.id,
                "use_outputs_from" to author.id,
                PHONE_DEVELOPMENT_MANIFEST_PARAMETER to "true"
            )
        )
        val legacyPlan = AgentPlanFactory.actions(
            request("Write and verify a Python program", screen, listOf(runtime), listOf(codex)),
            listOf(author, execute)
        )
        val completed = legacyPlan.markAction(
            author.id,
            AgentActionStatus.COMPLETED,
            AgentActionResult(author.id, true, manifest)
        )
        val materialized = completed.materializeToolInput(execute, allowOutputHandoff = false)
        val input = JSONObject(materialized.parameters.getValue("input_json"))

        assertEquals("python", input.getString("language"))
        val wrappedSource = input.getString("source")
        val encoded = java.util.Base64.getEncoder().encodeToString(generatedSource.toByteArray(Charsets.UTF_8))
        val filesPayload = Regex("""b64decode\(\"([^\"]+)\"\)""")
            .find(wrappedSource)?.groupValues?.get(1).orEmpty()
        val files = JSONArray(String(java.util.Base64.getDecoder().decode(filesPayload), Charsets.UTF_8))
        assertEquals("simple_average.py", files.getJSONObject(0).getString("path"))
        assertEquals(encoded, files.getJSONObject(0).getString("data"))
        assertFalse(wrappedSource.contains(generatedSource))
        assertEquals("simple_average.py", input.getJSONArray("artifact_paths").getString(0))
        assertEquals("simple_average.py", materialized.parameters[PHONE_DEVELOPMENT_FILE_PARAMETER])
        assertEquals("python simple_average.py", materialized.phoneDevelopmentDisplayCommand())
    }

    @Test
    fun materializesMultiFilePhoneProjectWithoutFlatteningDirectories() {
        val manifest = JSONObject()
            .put("schema", "galaxyssi.phone-development-manifest.v2")
            .put("language", "python")
            .put("entry_file", "src/main.py")
            .put("files", org.json.JSONArray()
                .put(JSONObject().put("path", "src/main.py").put("content", "from lib.maths import total\nprint(total([2, 3]))"))
                .put(JSONObject().put("path", "src/lib/maths.py").put("content", "def total(values):\n    return sum(values)")))
            .put("artifact_paths", org.json.JSONArray().put("README.md"))
        val parsed = AgentPhoneDevelopmentManifestCodec.parse(manifest.toString()).getOrThrow()
        val input = parsed.runtimeInput()

        assertEquals("src/main.py", parsed.entryFile)
        assertEquals(listOf("src/main.py", "src/lib/maths.py"), parsed.files.map { it.path })
        assertEquals(3, input.getJSONArray("artifact_paths").length())
        assertTrue(input.getString("source").contains("mkdir(parents=True"))
        assertTrue(input.getString("source").contains("runpy.run_path"))
        assertTrue(input.getString("source").contains("json.loads(base64.b64decode("))
        assertFalse(input.getString("source").contains("\\/"))
    }

    @Test
    fun returnsFailedPhoneVerificationToTheAuthoringModel() {
        val manifestAction = AgentAction(
            id = "author",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Prepare code",
            result = """{"schema":"galaxyssi.phone-development-manifest.v2","language":"python","entry_file":"main.py","files":[{"path":"main.py","content":"if True:\\nprint('broken')"}],"artifact_paths":[]}"""
        )
        val failedExecution = AgentAction(
            id = "execute",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone Linux",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.FAILED,
            description = "Run and verify",
            parameters = mapOf(
                "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE,
                "use_outputs_from" to manifestAction.id,
                PHONE_DEVELOPMENT_MANIFEST_PARAMETER to "true"
            ),
            result = "IndentationError: expected an indented block"
        )

        val prompt = AgentPhoneDevelopmentPolicy.repairPrompt(
            goal = "Write and verify a Python program",
            history = listOf(manifestAction, failedExecution),
            runtimeSummary = "python: ready; browser-automation: not installed"
        )

        assertNotNull(prompt)
        assertTrue(prompt.orEmpty().contains("Previous manifest"))
        assertTrue(prompt.orEmpty().contains("IndentationError"))
        assertTrue(prompt.orEmpty().contains("browser-automation: not installed"))
        assertTrue(prompt.orEmpty().contains("complete replacement JSON object"))
        val legacyProfilePlan = AgentPlanFactory.actions(
            request(
                "Write and verify a Python program",
                ScreenContext("com.galaxyssi.chat", pageTitle = "GalaxySSI"),
                emptyList()
            ),
            listOf(failedExecution.copy(status = AgentActionStatus.PENDING_CONFIRMATION))
        ).copy(plannerProfile = "rule-based-local")
        assertTrue(legacyProfilePlan.isPhoneDevelopmentRepairRequest(PHONE_DEVELOPMENT_REPLAN_REASON))
    }

    @Test
    fun insertsTrustedRuntimePackInstallationBeforePhoneExecution() {
        val author = AgentAction(
            id = "author",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Prepare code",
            parameters = mapOf("connector_task_mode" to PHONE_DEVELOPMENT_CONNECTOR_MODE)
        )
        val execute = AgentAction(
            id = "execute",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone Linux",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Run and verify",
            parameters = mapOf(
                "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE,
                "depends_on" to author.id,
                "use_outputs_from" to author.id,
                PHONE_DEVELOPMENT_MANIFEST_PARAMETER to "true"
            )
        )
        val manifest = JSONObject()
            .put("schema", "galaxyssi.phone-development-manifest.v2")
            .put("language", "python")
            .put("entry_file", "main.py")
            .put("files", org.json.JSONArray().put(
                JSONObject().put("path", "main.py").put("content", "print('ready')")
            ))
            .put("required_packs", org.json.JSONArray().put("node-js").put("browser-automation"))
            .put("artifact_paths", org.json.JSONArray())
            .toString()
        val plan = AgentPlanFactory.actions(
            request(
                "Build a browser script",
                ScreenContext("com.galaxyssi.chat", pageTitle = "GalaxySSI"),
                emptyList()
            ),
            listOf(author, execute)
        ).markAction(author.id, AgentActionStatus.COMPLETED, AgentActionResult(author.id, true, manifest))

        val expanded = plan.withPhoneDevelopmentPackInstalls(
            authorActionId = author.id,
            sourceResult = manifest,
            installedPackIds = setOf("linux-base", "python-uv", "node-js")
        )

        assertEquals(3, expanded.actions.size)
        val install = expanded.actions[1]
        assertEquals(AgentOnDeviceRuntimeTools.INSTALL_PACK, install.parameters["tool_id"])
        assertEquals("browser-automation", JSONObject(install.parameters.getValue("input_json")).getString("pack_id"))
        assertEquals(install.id, expanded.actions.last().parameters["depends_on"])
        assertEquals(author.id, expanded.actions.last().parameters["use_outputs_from"])
    }

    @Test
    fun routesRepositoryDevelopmentToTheSupervisedPhoneProjectMode() {
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("Build the entire Android repository with Gradle"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Build the entire Android repository with Gradle"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Fix the current GalaxySSI Android app and submit a pull request"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Clone https://github.com/galaxyssi/GalaxySSI and improve the Android project"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Clone the GalaxySSI repository on this phone and report the current branch"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Continue https://github.com/galaxyssi/GalaxySSI on this phone"))
        assertTrue(
            AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(
                "Clone https://github.com/galaxyssi/GalaxySSI, inspect the current branch and repository status, and report the verified result."
            )
        )
        assertTrue(
            AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(
                "Clone the GalaxySSI repository on this phone. Do not use Desktop workspace."
            )
        )
        assertTrue(
            AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(
                "\u5728\u624b\u673a\u672c\u673a\u514b\u9686 GalaxySSI \u4ed3\u5e93\uff0c\u4e0d\u8981\u4f7f\u7528 Desktop \u5de5\u4f5c\u533a"
            )
        )
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Inspect the current repository status and report any local changes"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Audit the GalaxySSI codebase without modifying files"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("\u5728\u624b\u673a\u672c\u673a\u514b\u9686 GalaxySSI \u4ed3\u5e93\uff0c\u4fee\u590d\u4ee3\u7801\u5e76\u63d0\u4ea4 GitHub PR"))
        assertFalse(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("Show the latest GitHub releases"))
        assertFalse(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("Explain how Git branches work"))

        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Write a Python program on the desktop"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Comprehensively test the app and desktop, including offline recovery and UI responsiveness"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Analyze this app screenshot and fix the issue"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("\u5168\u9762\u6d4b\u8bd5 App \u548c Desktop \u7684\u6240\u6709\u529f\u80fd\uff0c\u5305\u62ec\u79bb\u7ebf\u6062\u590d\u548c\u9875\u9762\u6d41\u7545\u5ea6"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("Write a simple Python program and verify it"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject("Write a simple Python program and verify it"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("\u5728\u624b\u673a\u672c\u673a\u5199\u4e00\u4e2a Python \u811a\u672c\u5e76\u6d4b\u8bd5"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("Run this Python script locally on the phone and verify it"))
        assertFalse(
            AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime(
                "\u5e94\u7528\u5076\u53d1\u95ea\u9000\u4e14\u53ea\u5728\u53d1\u9001\u6587\u5b57\u65f6\u51fa\u73b0\u3002\u5217\u51fa\u4e24\u4e2a\u4e92\u4e0d\u91cd\u590d\u7684\u53ef\u9a8c\u8bc1\u5047\u8bbe\u3002"
            )
        )
        val longProjectGoal = buildString {
            append("Fix the GalaxySSI Android project and submit a pull request. ")
            repeat(300) {
                append("Preserve existing behavior, inspect evidence, implement the requested change, and verify it. ")
            }
        }
        assertTrue(longProjectGoal.length > 4_000)
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(longProjectGoal))
    }

    @Test
    fun supervisedProjectStartsWithASelectedCapableAgentAndPhoneToolInventory() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val clone = nativeDescriptor(
            AgentMobileProjectNativeTools.CLONE,
            "Clone repository",
            AgentNativeToolRisk.MEDIUM
        )
        val codex = AgentCallableTarget(
            id = "codex-laptop",
            title = "Codex - Laptop",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING, AgentCapability.TASK_EXECUTION)
        )

        val plan = RuleBasedAgentPlanner().plan(
            request(
                "Clone https://github.com/galaxyssi/GalaxySSI and improve the Android project",
                screen,
                listOf(clone),
                listOf(codex)
            )
        )

        val action = plan.actions.single()
        assertEquals(AgentActionKind.CALL_CONNECTOR, action.kind)
        assertEquals("codex-laptop", action.parameters["connector_id"])
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, action.parameters["connector_task_mode"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, action.parameters[INTERNAL_TASK_EXECUTION_MODE])
        assertTrue(action.parameters.getValue("prompt").contains(AgentMobileProjectNativeTools.CLONE))
        assertTrue(action.parameters.getValue("prompt").contains("Return exactly one JSON ActionPlan"))
        assertTrue(action.parameters.getValue("prompt").contains("\"execution_location\":\"phone\""))
        assertTrue(action.parameters.getValue("prompt").contains("reasoning provider are independent"))
        assertTrue(action.parameters.getValue("prompt").contains("Desktop-hosted browser search"))
        assertFalse(action.parameters.getValue("prompt").contains("Available Desktop execution connectors"))
        assertTrue(action.parameters.getValue("prompt").contains("artifact_paths"))
        assertTrue(action.parameters.getValue("prompt").contains("Do not require an artifact for repository clone"))
        assertTrue(action.parameters.getValue("prompt").contains("verified ZIP"))
        assertTrue(action.parameters.getValue("prompt").contains(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH))
        assertTrue(action.parameters.getValue("prompt").contains("android-sdk"))
        assertTrue(action.parameters.getValue("prompt").contains("Gradle"))
    }

    @Test
    fun repositoryUrlDoesNotTurnAProjectOperationIntoWebResearch() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val clone = nativeDescriptor(
            AgentMobileProjectNativeTools.CLONE,
            "Clone repository",
            AgentNativeToolRisk.MEDIUM
        )
        val research = nativeDescriptor(
            AgentWebIntelligenceNativeTools.RESEARCH,
            "Research the public web",
            AgentNativeToolRisk.LOW
        )
        val localModel = AgentCallableTarget(
            id = "gemma-local",
            title = "Gemma Local",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING, AgentCapability.TASK_EXECUTION)
        )
        val request = request(
            "Clone https://github.com/galaxyssi/GalaxySSI on this phone and report the current branch",
            screen,
            listOf(clone, research),
            listOf(localModel)
        )

        val plan = RuleBasedAgentPlanner().plan(request)

        assertTrue(plan.isSupervisedProjectPlan())
        assertEquals(AgentActionKind.CALL_CONNECTOR, plan.actions.single().kind)
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, plan.actions.single().parameters["connector_task_mode"])
        assertFalse(plan.actions.any { it.parameters["tool_id"] in AgentWebIntelligenceNativeTools.toolIds })
    }

    @Test
    fun `temporarily unavailable Codex still keeps phone execution planning only`() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex Agent",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.DISCONNECTED,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING, AgentCapability.TASK_EXECUTION)
        )
        val goal = "Create a file named galaxyssi_phone_probe.txt in the phone project workspace, then verify it"

        val plan = RuleBasedAgentPlanner().plan(request(goal, screen, emptyList(), listOf(codex)))

        assertTrue(plan.isSupervisedProjectPlan())
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, plan.actions.single().parameters["connector_task_mode"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, plan.actions.single().parameters[INTERNAL_TASK_EXECUTION_MODE])
    }

    @Test
    fun `generic file execution request is planned by the model but executed on the phone`() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex Agent",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING, AgentCapability.TASK_EXECUTION)
        )
        val goal = "On my phone, create docs/probe.txt, read it back, and verify the content"

        val plan = RuleBasedAgentPlanner().plan(request(goal, screen, emptyList(), listOf(codex)))

        assertTrue(plan.isSupervisedProjectPlan())
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, plan.actions.single().parameters["connector_task_mode"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, plan.actions.single().parameters[INTERNAL_TASK_EXECUTION_MODE])
    }

    @Test
    fun supervisedProjectAppendsOneEvidenceReviewerAfterEveryToolBatch() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val clone = nativeDescriptor(
            AgentMobileProjectNativeTools.CLONE,
            "Clone repository",
            AgentNativeToolRisk.MEDIUM
        )
        val target = AgentCallableTarget(
            id = "qwen-local",
            title = "Qwen Local",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING)
        )
        val request = request(
            "Clone https://github.com/galaxyssi/GalaxySSI and improve the Android project",
            screen,
            listOf(clone),
            listOf(target)
        )
        val connector = RuleBasedAgentPlanner().supervisedProjectActions(request)!!.single()
        val tool = AgentAction(
            id = "clone-project",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = clone.title,
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Clone the repository",
            parameters = mapOf(
                "tool_id" to clone.id,
                "input_json" to "{\"workspace_id\":\"current\",\"repository_url\":\"https://github.com/galaxyssi/GalaxySSI\"}"
            ),
            requiresConfirmation = true
        )
        val batch = AgentPlanFactory.singleAction(request, tool).copy(
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
        )

        val reviewed = AgentSupervisedProjectLoop.appendReviewer(batch, connector, request, "test")

        assertEquals(2, reviewed.actions.size)
        val reviewer = reviewed.actions.last()
        assertTrue(reviewer.isSupervisedProjectConnector())
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, reviewer.parameters[INTERNAL_TASK_EXECUTION_MODE])
        assertEquals(listOf(tool.id), reviewer.dependencyIds())
        assertEquals(listOf(tool.id), reviewer.outputSourceIds())
    }

    @Test
    fun supervisedProjectReviewerHandsOffRecoveredEvidenceExactlyOnce() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val inspect = nativeDescriptor(
            AgentMobileProjectNativeTools.INSPECT,
            "Inspect repository",
            AgentNativeToolRisk.LOW
        )
        val target = AgentCallableTarget(
            id = "qwen-local",
            title = "Qwen Local",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING)
        )
        val baseRequest = request(
            "Continue https://github.com/galaxyssi/GalaxySSI on this phone",
            screen,
            listOf(inspect),
            listOf(target)
        )
        val connector = RuleBasedAgentPlanner().supervisedProjectActions(baseRequest)!!.single()
        val evidenceMarker = "UNIQUE_RECOVERED_NATIVE_EVIDENCE"
        val completed = AgentAction(
            id = "inspect-project",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = inspect.title,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Inspect the repository",
            parameters = mapOf("tool_id" to inspect.id, "input_json" to "{\"workspace_id\":\"current\"}"),
            requiresConfirmation = false,
            result = evidenceMarker
        )
        val recoveredRequest = baseRequest.copy(executionHistory = listOf(completed))
        val recoveredPlan = AgentPlanFactory.singleAction(recoveredRequest, completed).copy(
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
        )

        val reviewed = AgentSupervisedProjectLoop.appendReviewer(
            recoveredPlan,
            connector,
            recoveredRequest,
            "recovered"
        )
        val reviewer = reviewed.actions.last()
        val promptBeforeHandoff = reviewer.parameters.getValue("prompt")
        val materializedPrompt = reviewed.materializeToolInput(reviewer, allowOutputHandoff = true)
            .parameters.getValue("prompt")

        assertFalse(promptBeforeHandoff.contains(evidenceMarker))
        assertEquals(1, materializedPrompt.split(evidenceMarker).size - 1)
    }

    @Test
    fun supervisedProjectRepairsAPlanWhosePendingReviewerCannotRun() {
        val blockedDependency = AgentAction(
            id = "missing-dependency-reviewer",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.BLOCKED,
            description = "Review project evidence",
            parameters = mapOf(
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                "depends_on" to "missing-action"
            ),
            requiresConfirmation = false
        )
        val plan = AgentPlanFactory.actions(
            request(
                goal = "Continue the phone project",
                screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
                nativeTools = emptyList()
            ),
            listOf(blockedDependency)
        ).copy(
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
        )

        assertTrue(AgentSupervisedProjectLoop.needsRunnableReviewer(plan))
    }

    @Test
    fun supervisedProjectUsesAContinuousProgressGuardedExecutionBudget() {
        val budget = AgentModelPlannerSettings(
            maxActions = 4,
            maxReplans = 2,
            maxToolCalls = 8,
            maxLoopIterations = 5
        ).executionLoopBudget(
            AgentExecutionProfile.forGoal("Improve the Android project and run tests")
        )

        assertEquals(16, budget.maxIterations)
        assertEquals(24, budget.maxActions)
        assertEquals(MAX_SUPERVISED_REPLANS, budget.maxReplans)
        assertEquals(24, budget.maxToolCalls)
        assertFalse(budget.enforceCountLimits)
    }

    @Test
    fun modelExecutionSiteDecisionSeparatesReasoningFromExecutionAuthority() {
        val runtimeAction = AgentAction(
            id = "runtime",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "local-agent-runtime",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PROPOSED,
            description = "Run in the phone runtime",
            parameters = mapOf("tool_id" to AgentOnDeviceRuntimeTools.EXECUTE)
        )
        val workspaceAction = runtimeAction.copy(
            id = "workspace",
            parameters = mapOf("tool_id" to AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT)
        )
        val connectorAction = AgentAction(
            id = "connector",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex Agent",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            description = "Send to Codex",
            parameters = mapOf("connector_id" to "codex")
        )
        val phone = AgentExecutionSiteDecisionCodec.parse(
            "{\"execution_location\":\"phone\",\"execution_location_evidence\":\"\"}",
            "Use Codex to write and verify a program"
        )
        val desktop = AgentExecutionSiteDecisionCodec.parse(
            "{\"execution_location\":\"desktop\",\"execution_location_evidence\":\"on my Desktop\"}",
            "Build this on my Desktop with Codex"
        )

        assertEquals(AgentRequestedExecutionSite.PHONE, phone?.site)
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(phone!!, listOf(runtimeAction, workspaceAction)))
        assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(phone, listOf(connectorAction)))
        assertEquals(AgentRequestedExecutionSite.DESKTOP, desktop?.site)
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(desktop!!, listOf(connectorAction)))
        assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(desktop, listOf(runtimeAction)))
        assertEquals(
            null,
            AgentExecutionSiteDecisionCodec.parse(
                "{\"execution_location\":\"desktop\",\"execution_location_evidence\":\"faster machine\"}",
                "Build this project"
            )
        )
    }

    @Test
    fun acceptsModelPlannedPhoneWorkspaceCreateAndReadGraph() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val nativeTools = listOf(
            nativeDescriptor(
                AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
                "Create a text file in the phone workspace",
                AgentNativeToolRisk.MEDIUM
            ),
            nativeDescriptor(
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                "Read a text file from the phone workspace",
                AgentNativeToolRisk.LOW
            )
        )
        val goal = "On this phone, create docs/model_reasoning_probe.txt with content PHONE_REASONING_OK, read it back, and verify it."
        val request = request(goal, screen, nativeTools)
        val raw = """
            {
              "execution_location":"phone",
              "summary":"Create the target file in the phone workspace, then read it back and verify its content.",
              "actions":[
                {
                  "ref":"create_probe_file",
                  "kind":"CALL_NATIVE_TOOL",
                  "target":"galaxyssi.workspace.file.create.text",
                  "description":"Create the verification file",
                  "depends_on":[],
                  "use_outputs_from":[],
                  "parameters":{
                    "tool_id":"galaxyssi.workspace.file.create.text",
                    "arguments":{
                      "workspace_id":"current",
                      "path":"docs/model_reasoning_probe.txt",
                      "text":"PHONE_REASONING_OK",
                      "create_parents":true
                    }
                  }
                },
                {
                  "ref":"read_probe_file",
                  "kind":"CALL_NATIVE_TOOL",
                  "target":"galaxyssi.workspace.file.read.text",
                  "description":"Read the verification file",
                  "depends_on":["create_probe_file"],
                  "use_outputs_from":[],
                  "parameters":{
                    "tool_id":"galaxyssi.workspace.file.read.text",
                    "arguments":{
                      "workspace_id":"current",
                      "path":"docs/model_reasoning_probe.txt",
                      "max_bytes":64
                    }
                  }
                }
              ]
            }
        """.trimIndent()

        val site = requireNotNull(AgentExecutionSiteDecisionCodec.parse(raw, goal))
        val plan = requireNotNull(
            AgentModelPlanParser.parse(
                request,
                raw,
                AgentModelPlannerSettings(
                    maxActions = 8,
                    multiAgentCoordination = true,
                    maxAgentHops = 8
                )
            )
        )

        assertEquals(AgentRequestedExecutionSite.PHONE, site.site)
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(site, plan.actions))
        assertEquals(2, plan.actions.size)
        assertTrue(plan.actions.all { it.kind == AgentActionKind.CALL_NATIVE_TOOL })
        assertEquals(plan.actions.first().id, plan.actions.last().parameters["depends_on"])
    }

    @Test
    fun routesCrossProductTestingThroughTheModelExecutionSiteDecision() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val runtime = nativeDescriptor(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "Execute in the on-device Linux sandbox",
            AgentNativeToolRisk.MEDIUM
        )
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE, AgentCapability.REASONING)
        )

        val plan = RuleBasedAgentPlanner().plan(
            request(
                "Comprehensively test the app and desktop, including offline recovery and UI responsiveness",
                screen,
                listOf(runtime),
                listOf(codex)
            )
        )

        assertTrue(plan.isSupervisedProjectPlan())
        assertEquals(listOf(AgentActionKind.CALL_CONNECTOR), plan.actions.map { it.kind })
        assertEquals("codex", plan.actions.single().parameters["connector_id"])
        assertEquals(PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, plan.actions.single().parameters["connector_task_mode"])
        assertFalse(plan.actions.any { it.parameters["tool_id"] == AgentOnDeviceRuntimeTools.EXECUTE })
    }

    @Test
    fun rendersUnavailablePackageAsNaturalActionableFailure() {
        val english = renderPackageUnavailable("com.galaxyssi.missing", zh = false)
        assertTrue(english.contains("com.galaxyssi.missing"))
        assertTrue(english.contains("Check the package name"))
        assertFalse(english.contains("expose"))

        val chinese = renderPackageUnavailable("com.galaxyssi.missing", zh = true)
        assertTrue(chinese.contains("com.galaxyssi.missing"))
        assertFalse(chinese.contains("GalaxySSI"))
    }

    @Test
    fun rendersPhoneWebSearchAsConciseLinkedResults() {
        val rendered = renderPhoneWebSearchResult(
            mapOf(
                "results" to listOf(
                    mapOf("title" to "First headline", "url" to "https://example.com/first"),
                    mapOf("title" to "Second headline", "url" to "https://example.com/second")
                )
            ),
            zh = false
        )

        assertEquals(
            "Latest web results:\n- [First headline](https://example.com/first)\n- [Second headline](https://example.com/second)",
            rendered
        )
        assertFalse(rendered.contains("provider"))
        assertFalse(rendered.contains("retrieved_at"))
    }

    @Test
    fun leavesGenericWebDecisionToTheSelectedReasoningModel() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val webTool = nativeDescriptor(
            AgentWebIntelligenceNativeTools.RESEARCH,
            "Build a cited research evidence pack",
            AgentNativeToolRisk.LOW
        )
        val codex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.RESEARCH, AgentCapability.LIVE_DATA, AgentCapability.TOOL_USE)
        )
        val remotePlan = RuleBasedAgentPlanner().plan(request("Latest technology news today", screen, listOf(webTool), listOf(codex)))
        assertEquals(1, remotePlan.actions.size)
        assertEquals(AgentActionKind.CALL_CONNECTOR, remotePlan.actions.single().kind)
        assertFalse(remotePlan.actions.single().parameters.containsKey("web_execution_location"))
        assertFalse(remotePlan.actions.any { it.kind == AgentActionKind.CALL_NATIVE_TOOL })

        val cloud = codex.copy(id = "cloud-models", title = "Cloud Models", kind = AgentConnectorKind.MODEL)
        val cloudPlan = RuleBasedAgentPlanner().plan(request("Shanghai weather today", screen, listOf(webTool), listOf(cloud)))
        assertEquals(1, cloudPlan.actions.size)
        assertEquals(AgentActionKind.CALL_CONNECTOR, cloudPlan.actions.single().kind)
        assertFalse(cloudPlan.actions.single().parameters.containsKey("web_execution_location"))

        val toolLessModel = cloud.copy(id = "local-llm", title = "Local LLM", capabilities = listOf(AgentCapability.CHAT))
        val fallbackPlan = RuleBasedAgentPlanner().plan(request("Latest technology news today", screen, listOf(webTool), listOf(toolLessModel)))
        assertEquals(listOf(AgentActionKind.CALL_CONNECTOR), fallbackPlan.actions.map { it.kind })
        assertFalse(fallbackPlan.actions.single().parameters.containsKey("web_execution_location"))
        assertFalse(fallbackPlan.actions.any { it.kind == AgentActionKind.CALL_NATIVE_TOOL })
    }

    @Test
    fun temporaryDisconnectedConnectorDoesNotFallBackToLocalAgentRuntime() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val recoveringCodex = AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.DISCONNECTED,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING, AgentCapability.RESEARCH)
        )

        val plan = RuleBasedAgentPlanner().plan(
            request("Explain why the sky is blue", screen, emptyList(), listOf(recoveringCodex))
        )

        assertEquals(AgentActionKind.CALL_CONNECTOR, plan.actions.single().kind)
        assertEquals("codex", plan.actions.single().parameters["connector_id"])
        assertFalse(plan.actions.any { action -> action.target == "local-agent-runtime" })
    }

    @Test
    fun explicitRecoveringCodexUsesPairedContactIdInsteadOfHardCodedAlias() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val recoveringCodex = AgentCallableTarget(
            id = "desktop-installation-123:codex",
            title = "Codex Agent - Desktop",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.DISCONNECTED,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING),
            desktopAccessProfile = GalaxySSILinkProtocol.ACCESS_DESKTOP_EXECUTOR
        )

        val plan = RuleBasedAgentPlanner().plan(
            request("Use Codex Agent. Reply with only OK.", screen, emptyList(), listOf(recoveringCodex))
        )

        assertEquals(recoveringCodex.id, plan.actions.single().parameters["connector_id"])
        assertEquals(AgentRouteKind.DESKTOP_AGENT, plan.route.kind)
        assertTrue(plan.requiredPermissions.single { it.id == "paired_contact" }.granted)
    }

    @Test
    fun missingReasoningProviderReportsUnavailableInsteadOfLocalRuntime() {
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")

        val plan = RuleBasedAgentPlanner().plan(request("Explain why the sky is blue", screen, emptyList()))

        assertEquals(AgentActionKind.CALL_CONNECTOR, plan.actions.single().kind)
        assertEquals("reasoning-provider-unavailable", plan.actions.single().parameters["connector_id"])
        assertFalse(plan.actions.any { action -> action.target == "local-agent-runtime" })
    }

    @Test
    fun ordinaryConnectorResearchDoesNotInheritPhoneToolConsentTerms() {
        val action = AgentAction(
            id = "connector-codex",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Research current information",
            parameters = mapOf("connector_id" to "codex", "prompt" to "Find the current location of the event")
        )

        assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(action))
    }

    @Test
    fun recognizesChinesePhoneCameraCommands() {
        assertTrue(AgentSystemToolPlanner.isCameraCaptureGoal("\u8c03\u7528\u624b\u673a\u6444\u50cf\u5934\u62cd\u7167"))
        assertTrue(AgentSystemToolPlanner.isCameraCaptureGoal("\u6253\u5f00\u76f8\u673a\u62cd\u7167"))
        assertTrue(AgentSystemToolPlanner.isCameraCaptureGoal("\u4f7f\u7528\u6444\u50cf\u5934\u62cd\u7167"))
        assertTrue(AgentSystemToolPlanner.isCameraCaptureGoal("\u6253\u5f00\u76f8\u673a"))
        assertTrue(AgentSystemToolPlanner.isCameraCaptureGoal("\u62cd\u7167"))
    }

    @Test
    fun doesNotTreatCameraDiscussionAsAnAction() {
        assertFalse(AgentSystemToolPlanner.isCameraCaptureGoal("Explain how a camera sensor works"))
        assertFalse(AgentSystemToolPlanner.isCameraCaptureGoal("\u5206\u6790\u6444\u50cf\u5934\u7684\u539f\u7406"))
    }

    @Test
    fun recognizesBoundedMicrophoneRecordingCommands() {
        assertTrue(AgentSystemToolPlanner.isMicrophoneCaptureGoal("record audio for five seconds"))
        assertTrue(AgentSystemToolPlanner.isMicrophoneCaptureGoal("\u5f55\u97f3 5 \u79d2"))
        assertFalse(AgentSystemToolPlanner.isMicrophoneCaptureGoal("Explain how microphones work"))
    }

    @Test
    fun parsesSpokenTimerDurations() {
        assertTrue(AgentSystemToolPlanner.timerSecondsForGoal("set timer one minute") == 60)
        assertTrue(AgentSystemToolPlanner.timerSecondsForGoal("set timer fifteen seconds") == 15)
        assertTrue(AgentSystemToolPlanner.timerSecondsForGoal("set timer 2 hours") == 7_200)
        assertTrue(AgentSystemToolPlanner.timerSecondsForGoal("\u8bbe\u7f6e3\u5206\u949f\u5012\u8ba1\u65f6") == 180)
    }

    @Test
    fun compoundRepositoryAuditCannotBeHijackedByMemoryStatusShortcut() {
        val nativeTools = listOf(
            nativeDescriptor(AgentHardwareNativeTools.MEMORY_STATUS, "Read phone memory status", AgentNativeToolRisk.LOW)
        )
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val planner = RuleBasedAgentPlanner()
        val chineseAudit =
            "\u8bf7\u5728\u624b\u673a\u672c\u673a Linux \u4e2d\u5bf9 GalaxySSI \u4ed3\u5e93\u505a\u5b8c\u6574\u9a8c\u6536\uff0c" +
                "\u6838\u5bf9 Git \u72b6\u6001\u3001Android \u548c Desktop \u7248\u672c\u3001\u53ef\u7528\u5185\u5b58\u3001" +
                "\u78c1\u76d8\u3001CPU\u3001\u7f51\u7edc\u3001\u6d4b\u8bd5\u4e0e\u6784\u5efa\u5165\u53e3\uff0c\u7136\u540e\u6839\u636e\u89c2\u5bdf\u91cd\u65b0\u89c4\u5212\u3002"

        assertEquals(null, planner.deterministicLocalAction(request(chineseAudit, screen, nativeTools)))
        assertEquals(
            null,
            planner.deterministicLocalAction(
                request(
                    "Audit this repository, inspect available memory, Git, builds, tests, and replan from the evidence.",
                    screen,
                    nativeTools
                )
            )
        )
    }

    @Test
    fun multiplePhoneOperationsBypassWholeGoalShortcutButStillPlanPerSegment() {
        val nativeTools = listOf(
            nativeDescriptor(AgentHardwareNativeTools.FLASHLIGHT_SET, "Request flashlight state", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentHardwareNativeTools.BATTERY_STATUS, "Read battery status", AgentNativeToolRisk.LOW)
        )
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI")
        val request = request("Turn on the flashlight and then read the current battery level", screen, nativeTools)
        val planner = RuleBasedAgentPlanner()

        assertEquals(null, planner.deterministicLocalAction(request))
        assertEquals(2, planner.actionsFor(request).size)
    }

    @Test
    fun routesDirectChinesePhoneOperationsLocally() {
        val nativeTools = listOf(
            nativeDescriptor(AgentHardwareNativeTools.FLASHLIGHT_SET, "Request flashlight state", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentHardwareNativeTools.BATTERY_STATUS, "Read battery status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.POWER_STATUS, "Read power status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.MEMORY_STATUS, "Read phone memory status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.STORAGE_STATUS, "Read storage status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.NETWORK_STATUS, "Read network status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentWebMediaNativeTools.WEB_SEARCH, "Search the public web", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.LOCATION_FOREGROUND_READ, "Read location", AgentNativeToolRisk.HIGH),
            nativeDescriptor(AgentHardwareNativeTools.SENSORS_LIST, "List sensors", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.SENSOR_SAMPLE, "Read sensor", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentHardwareNativeTools.BLUETOOTH_STATUS, "Read Bluetooth status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.NFC_STATUS, "Read NFC status", AgentNativeToolRisk.LOW),
            nativeDescriptor(AgentHardwareNativeTools.INSTALLED_APPS_LIST, "List installed apps", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentHardwareNativeTools.PACKAGE_DETAIL, "Read package detail", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET, "Set Android stream volume", AgentNativeToolRisk.MEDIUM),
            nativeDescriptor(AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF, "Open Android dialer", AgentNativeToolRisk.HIGH),
            nativeDescriptor(AgentAndroidSystemNativeTools.SMS_SEND, "Send SMS message", AgentNativeToolRisk.HIGH)
        )
        val screen = ScreenContext(
            foregroundApp = "com.galaxyssi.chat",
            pageTitle = "GalaxySSI",
            installedApps = listOf(InstalledAppInfo("com.tencent.mm", "WeChat"))
        )
        val planner = RuleBasedAgentPlanner()

        val flashlight = planner.deterministicLocalAction(request("\u6253\u5f00\u624b\u7535\u7b52", screen, nativeTools))
        assertEquals(AgentActionKind.CALL_NATIVE_TOOL, flashlight?.kind)
        assertEquals(AgentHardwareNativeTools.FLASHLIGHT_SET, flashlight?.parameters?.get("tool_id"))
        assertTrue(JSONObject(flashlight?.parameters?.get("input_json").orEmpty()).getBoolean("enabled"))
        assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(requireNotNull(flashlight)))

        val englishFlashlightOn = planner.deterministicLocalAction(request("Turn on the flashlight", screen, nativeTools))
        assertEquals(AgentHardwareNativeTools.FLASHLIGHT_SET, englishFlashlightOn?.parameters?.get("tool_id"))
        assertTrue(JSONObject(englishFlashlightOn?.parameters?.get("input_json").orEmpty()).getBoolean("enabled"))

        val englishFlashlightOff = planner.deterministicLocalAction(request("Turn off the flashlight", screen, nativeTools))
        assertEquals(AgentHardwareNativeTools.FLASHLIGHT_SET, englishFlashlightOff?.parameters?.get("tool_id"))
        assertFalse(JSONObject(englishFlashlightOff?.parameters?.get("input_json").orEmpty()).getBoolean("enabled"))

        val chineseBattery = planner.deterministicLocalAction(request("\u67e5\u770b\u624b\u673a\u7535\u91cf", screen, nativeTools))
        assertEquals(
            AgentHardwareNativeTools.BATTERY_STATUS,
            chineseBattery?.parameters?.get("tool_id")
        )
        assertEquals("zh", chineseBattery?.parameters?.get("response_language"))
        listOf(
            "\u8bfb\u53d6\u8fd9\u53f0\u624b\u673a\u7684\u5f53\u524d\u7535\u91cf\uff0c\u7b80\u77ed\u56de\u7b54\u3002",
            "\u8fd9\u53f0\u624b\u673a\u8fd8\u6709\u591a\u5c11\u7535\u91cf\uff1f",
            "Read the current battery level on this phone."
        ).forEach { goal ->
            assertEquals(
                goal,
                AgentHardwareNativeTools.BATTERY_STATUS,
                planner.deterministicLocalAction(request(goal, screen, nativeTools))?.parameters?.get("tool_id")
            )
        }
        assertEquals(
            "en",
            planner.deterministicLocalAction(
                request("Read the current battery level on this phone.", screen, nativeTools)
            )?.parameters?.get("response_language")
        )
        assertEquals(
            AgentHardwareNativeTools.POWER_STATUS,
            planner.deterministicLocalAction(request("Check battery saver status", screen, nativeTools))?.parameters?.get("tool_id")
        )
        listOf(
            "\u67e5\u4e0b\u624b\u673a\u5185\u5b58",
            "\u8fd9\u53f0\u624b\u673a\u8fd8\u6709\u591a\u5c11\u8fd0\u884c\u5185\u5b58\uff1f",
            "Check available RAM on this phone"
        ).forEach { goal ->
            val action = requireNotNull(planner.deterministicLocalAction(request(goal, screen, nativeTools)))
            assertEquals(goal, AgentHardwareNativeTools.MEMORY_STATUS, action.parameters["tool_id"])
            assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(action))
        }
        assertEquals(
            AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET,
            planner.deterministicLocalAction(request("\u628a\u97f3\u91cf\u8bbe\u7f6e\u4e3a50", screen, nativeTools))?.parameters?.get("tool_id")
        )
        val englishVolume = requireNotNull(
            planner.deterministicLocalAction(request("Set media volume 30", screen, nativeTools))
        )
        assertEquals(AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET, englishVolume.parameters["tool_id"])
        assertEquals("music", JSONObject(englishVolume.parameters.getValue("input_json")).getString("stream"))
        assertEquals(30, JSONObject(englishVolume.parameters.getValue("input_json")).getInt("percent"))
        assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(englishVolume))
        val dial = requireNotNull(planner.deterministicLocalAction(request("Dial 12345", screen, nativeTools)))
        assertEquals(AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF, dial.parameters["tool_id"])
        assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(dial))
        val sms = requireNotNull(planner.deterministicLocalAction(request("Send SMS to 12345: hello", screen, nativeTools)))
        assertEquals(AgentAndroidSystemNativeTools.SMS_SEND, sms.parameters["tool_id"])
        assertEquals(AgentConfirmationTier.DIRECT, AgentConfirmationPolicy.tier(sms))
        mapOf(
            "\u67e5\u770b\u7701\u7535\u6a21\u5f0f" to AgentHardwareNativeTools.POWER_STATUS,
            "\u67e5\u770b\u624b\u673a\u5185\u5b58" to AgentHardwareNativeTools.MEMORY_STATUS,
            "\u67e5\u770b\u624b\u673a\u5b58\u50a8" to AgentHardwareNativeTools.STORAGE_STATUS,
            "\u67e5\u770b\u624b\u673a\u7f51\u7edc\u72b6\u6001" to AgentHardwareNativeTools.NETWORK_STATUS,
            "\u83b7\u53d6\u5f53\u524d\u4f4d\u7f6e" to AgentHardwareNativeTools.LOCATION_FOREGROUND_READ,
            "\u5217\u51fa\u624b\u673a\u4f20\u611f\u5668" to AgentHardwareNativeTools.SENSORS_LIST,
            "\u8bfb\u53d6\u9640\u87ba\u4eea\u4f20\u611f\u5668" to AgentHardwareNativeTools.SENSOR_SAMPLE,
            "\u67e5\u770b\u84dd\u7259\u72b6\u6001" to AgentHardwareNativeTools.BLUETOOTH_STATUS,
            "\u67e5\u770bNFC\u72b6\u6001" to AgentHardwareNativeTools.NFC_STATUS,
            "\u5217\u51fa\u5df2\u5b89\u88c5\u5e94\u7528" to AgentHardwareNativeTools.INSTALLED_APPS_LIST,
            "package detail com.galaxyssi.chat" to AgentHardwareNativeTools.PACKAGE_DETAIL
        ).forEach { (goal, expectedTool) ->
            assertEquals(
                goal,
                expectedTool,
                planner.deterministicLocalAction(request(goal, screen, nativeTools))?.parameters?.get("tool_id")
            )
        }
        val sensorInput = JSONObject(
            planner.deterministicLocalAction(request("\u8bfb\u53d6\u9640\u87ba\u4eea\u4f20\u611f\u5668", screen, nativeTools))
                ?.parameters?.get("input_json").orEmpty()
        )
        assertEquals("gyroscope", sensorInput.getString("type"))
        val appSearch = requireNotNull(
            planner.deterministicLocalAction(request("Search installed apps GalaxySSI", screen, nativeTools))
        )
        assertEquals(AgentHardwareNativeTools.INSTALLED_APPS_LIST, appSearch.parameters["tool_id"])
        assertEquals("GalaxySSI", JSONObject(appSearch.parameters.getValue("input_json")).getString("query"))
        assertEquals("read-device-status", planner.deterministicLocalAction(request("\u67e5\u770b\u624b\u673a\u72b6\u6001", screen, nativeTools))?.id)
        val openWeChat = requireNotNull(
            planner.deterministicLocalAction(request("\u6253\u5f00WeChat", screen, nativeTools))
        )
        assertEquals("open-installed-app", openWeChat.id)
        assertEquals(AgentActionKind.OPEN_APP, openWeChat.kind)
        assertEquals("android-local", openWeChat.parameters["execution_scope"])
        val missingPhoneApp = requireNotNull(
            planner.deterministicLocalAction(request("\u6253\u5f00\u4e0d\u5b58\u5728\u7684\u5e94\u7528", screen, nativeTools))
        )
        assertEquals("open-installed-app-unavailable", missingPhoneApp.id)
        assertEquals(AgentActionKind.OPEN_APP, missingPhoneApp.kind)
        assertEquals("", missingPhoneApp.parameters["package"])
        assertEquals(
            null,
            planner.deterministicLocalAction(request("\u5728\u7535\u8111\u4e0a\u6253\u5f00\u5fae\u4fe1", screen, nativeTools))
        )
        val camera = requireNotNull(planner.deterministicLocalAction(request("\u6253\u5f00\u76f8\u673a", screen, nativeTools)))
        assertEquals("open-camera", camera.id)
        assertEquals(AgentActionKind.CALL_NATIVE_TOOL, camera.kind)
        assertEquals(AgentVisibleCaptureNativeTools.CAMERA_CAPTURE, camera.parameters["tool_id"])
        val microphone = requireNotNull(planner.deterministicLocalAction(request("\u5f55\u97f3 8 \u79d2", screen, nativeTools)))
        assertEquals(AgentActionKind.CALL_NATIVE_TOOL, microphone.kind)
        assertEquals(AgentVisibleCaptureNativeTools.MICROPHONE_RECORD, microphone.parameters["tool_id"])
        assertEquals(8, JSONObject(microphone.parameters.getValue("input_json")).getInt("max_duration_seconds"))
        assertEquals("set-timer", planner.deterministicLocalAction(request("\u8bbe\u7f6e3\u5206\u949f\u5012\u8ba1\u65f6", screen, nativeTools))?.id)
        assertNotNull(planner.deterministicLocalAction(request("\u5173\u95ed\u624b\u7535\u7b52", screen, nativeTools)))
    }

    private fun request(
        goal: String,
        screen: ScreenContext,
        nativeTools: List<AgentNativeToolDescriptor>,
        targets: List<AgentCallableTarget> = emptyList()
    ): AgentRequest = AgentRequest(
        goal = goal,
        screen = screen,
        targets = targets,
        memories = emptyList(),
        runtimeContext = AgentRuntimeContextBuilder.build(
            sessionId = "test",
            goal = goal,
            screen = screen,
            permissionMode = PermissionMode.AUTO_LOW_RISK,
            highRiskGuard = true,
            memoryCapture = false,
            callableTargets = targets,
            memories = emptyList(),
            nativeTools = nativeTools
        )
    )

    private fun nativeDescriptor(
        id: String,
        title: String,
        risk: AgentNativeToolRisk
    ): AgentNativeToolDescriptor = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = title,
        description = title,
        location = AgentNativeToolLocation.PHONE,
        inputSchema = AgentNativeJsonSchema(mapOf("type" to "object")),
        outputSchema = AgentNativeJsonSchema(mapOf("type" to "object")),
        risk = risk
    )
}
