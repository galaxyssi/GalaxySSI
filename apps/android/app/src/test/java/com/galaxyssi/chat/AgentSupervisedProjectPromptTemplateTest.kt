package com.galaxyssi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptTemplateTest {
    @Test fun `completion obligations come from model interpreted intent without implicit publication`() {
        for (continuation in listOf(false, true)) {
            val prompt = AgentSupervisedProjectPromptTemplate.render(context(), continuation, 240)
            assertTrue(prompt.contains("Declare root completion_requirements="))
            assertTrue(prompt.contains("respecting exclusions"))
            assertTrue(prompt.contains("No default publication"))
            assertTrue(prompt.contains("explain changes in reason"))
            assertFalse(prompt.contains("Unless local-only"))
            assertFalse(prompt.contains("unless local-only"))
        }
    }

    @Test
    fun `planning and recovery require observed model authored final answers`() {
        for (evidenceExpected in listOf(false, true)) {
            val prompt = AgentSupervisedProjectPromptTemplate.render(context(), evidenceExpected, 240)
            assertTrue(prompt.contains("other receipts need model review"))
            assertTrue(prompt.contains("After evidence proves completion"))
            assertTrue(prompt.contains("one DRAFT_PLAN: target=task-complete"))
            assertTrue(prompt.contains("description=final answer in user's language"))
            assertTrue(prompt.contains("Never repeat tools to finish or output diagnostic receipts"))
            assertTrue(prompt.contains("Set completes_goal=true only when verified commit/push/PR receipts"))
        }
    }

    @Test
    fun `advertises batch exact edits with resource ordering`() {
        val prompt = AgentSupervisedProjectPromptTemplate.render(context(), false, 240)

        assertTrue(prompt.contains("galaxyssi.workspace.files.patch.exact.batch"))
        assertTrue(prompt.contains("patches: galaxyssi.workspace.files.patch.exact.batch"))
        assertTrue(prompt.contains("order conflicts/runtime/publication"))
    }

    @Test
    fun `directs related source observations through bounded batches`() {
        val prompt = AgentSupervisedProjectPromptTemplate.render(context(), false, 20_000)

        assertTrue(prompt.contains("galaxyssi.workspace.files.read.text.batch"))
        assertTrue(prompt.contains("galaxyssi.workspace.files.search.text.batch"))
        assertTrue(prompt.contains("Batch reads/searches"))
        assertTrue(prompt.contains("known_sha256"))
    }

    @Test
    fun `prefers one phone linux repository observation for related git evidence`() {
        val prompt = AgentSupervisedProjectPromptTemplate.render(context(), false, 20_000)

        assertTrue(prompt.contains(AgentMobileProjectNativeTools.OBSERVE))
        assertTrue(prompt.contains("repository.observe for status/diff/history"))
    }

    @Test
    fun `same catalog and mode reuse the compiled prefix`() {
        val context = context()

        val first = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val second = AgentSupervisedProjectPromptTemplate.render(context, false, 240)

        assertSame(first, second)
    }

    @Test
    fun `planning and continuation keep separate compiled prefixes`() {
        val context = context()

        val planning = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val continuation = AgentSupervisedProjectPromptTemplate.render(context, true, 240)

        assertNotSame(planning, continuation)
        assertTrue(planning.startsWith("Plan the next Android tool graph."))
        assertTrue(continuation.startsWith("Continue the Android project from verified evidence."))
        assertTrue(planning.contains("Available phone tools:\n- ${AgentMobileProjectNativeTools.CLONE} |"))
        assertTrue(continuation.contains("Available phone tools:\n- ${AgentMobileProjectNativeTools.CLONE} |"))
        for (prompt in listOf(planning, continuation)) {
            assertTrue(prompt.contains("Up to 64 actions per response, not lifetime"))
            assertTrue(prompt.contains("Native depends_on uses earlier refs"))
            assertTrue(prompt.contains("wait for the receipt; failure blocks dependents"))
            assertTrue(prompt.contains("Native use_outputs_from=[]"))
            assertTrue(prompt.contains("Independent reads/disjoint mutations may run concurrently"))
            assertTrue(prompt.contains("order conflicts/runtime/publication"))
            assertTrue(prompt.contains("Only last action may complete, depending on all others"))
            assertFalse(prompt.contains("3-12 independent"))
            assertFalse(prompt.contains("Never batch runtime, install"))
        }
        assertTrue(planning.contains("start_line/max_lines"))
        assertTrue(continuation.contains("start_line/max_lines"))
    }

    @Test
    fun `working set omits only blocked tools and compiles a new reusable prefix`() {
        val context = context()
        val blocked = setOf(AgentMobileProjectNativeTools.CLONE)

        val full = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val focused = AgentSupervisedProjectPromptTemplate.render(
            context = context,
            evidenceExpected = false,
            maximumSchemaCharacters = 240,
            temporarilyBlockedToolIds = blocked
        )
        val focusedAgain = AgentSupervisedProjectPromptTemplate.render(
            context = context,
            evidenceExpected = false,
            maximumSchemaCharacters = 240,
            temporarilyBlockedToolIds = blocked
        )

        assertNotSame(full, focused)
        assertSame(focused, focusedAgain)
        assertTrue(focused.length < full.length)
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.CLONE} |"))
        assertTrue(focused.contains("- ${AgentMobileProjectNativeTools.CREATE_PULL_REQUEST} |"))
        assertTrue(focused.contains("phase-blocked tools reappear when evidence changes"))
    }

    private fun context(): AgentRuntimeContext {
        fun tool(id: String) = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = id,
            description = "Phone project tool",
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf("workspace_id" to AgentNativeJsonSchema.string())
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW
        )
        val tools = listOf(
            tool(AgentMobileProjectNativeTools.CLONE),
            tool(AgentMobileProjectNativeTools.OBSERVE),
            tool(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT_BATCH)
        )
        return AgentRuntimeContext(
            sessionId = "template-test",
            goal = "Improve the phone project",
            screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI"),
            permissionMode = PermissionMode.FULL_ACCESS,
            highRiskGuard = false,
            memoryCapture = false,
            systemTools = emptyList(),
            nativeTools = tools,
            callableTargets = emptyList(),
            memories = emptyList(),
            knowledgeItems = emptyList(),
            knowledgeStats = AgentKnowledgeStats(),
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = tools,
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
    }
}
