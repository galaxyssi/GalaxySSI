package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class LocalModelAgentToolPolicyTest {
    @Test fun ordinaryLocalModelCanInspectContractsDiagnoseInstallAndUseTheConversationWorkspace() {
        val ids = LocalModelAgentToolPolicy.toolIds(false, false)
        assertTrue(ids.containsAll(LocalModelWebToolProtocol.toolIds))
        assertTrue(ids.containsAll(AgentOnDeviceRuntimeTools.toolIds))
        assertTrue(ids.containsAll(AgentLinuxSoftwareNativeTools.toolIds))
        assertTrue(AgentToolInspectionTools.DESCRIBE in ids)
        assertTrue(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT in ids)
        assertTrue(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH in ids)
        assertTrue(AgentDesktopRemoteNativeTools.toolIds.none(ids::contains))
        assertTrue(AgentInteractiveBrowserTools.toolIds.none(ids::contains))
    }

    @Test fun researchAssignmentAndPublicationRepairRetainTheirOriginalScopedViews() {
        assertEquals(LocalModelWebToolProtocol.toolIds(true), LocalModelAgentToolPolicy.toolIds(true, false))
        assertEquals(setOf(CollaborationRecallNativeTool.ID), LocalModelAgentToolPolicy.toolIds(true, true))
        assertFalse(AgentOnDeviceRuntimeTools.EXECUTE in LocalModelAgentToolPolicy.toolIds(true, false))
        assertFalse(AgentDesktopRemoteNativeTools.TERMINAL_RUN in LocalModelAgentToolPolicy.toolIds(true, true))
    }

    @Test fun interactiveBrowserRequiresOwnedOrdinaryDispatchAndDoesNotBroadenResearchAssignments() {
        val ids = LocalModelAgentToolPolicy.toolIds(false, false, interactiveBrowser = true)
        assertTrue(ids.containsAll(AgentInteractiveBrowserTools.toolIds))
        assertTrue(AgentDesktopRemoteNativeTools.toolIds.none(ids::contains))
        assertEquals(LocalModelAgentToolPolicy.toolIds(true, false),
            LocalModelAgentToolPolicy.toolIds(true, false, interactiveBrowser = true))
        assertEquals(LocalModelAgentToolPolicy.toolIds(true, true),
            LocalModelAgentToolPolicy.toolIds(true, true, interactiveBrowser = true))
    }

    @Test fun workspacesMatchOtherPhoneToolsStayStableAcrossTurnsAndIsolateConversations() {
        val workspace = LocalModelAgentToolPolicy.workspace("conversation", "session")
        assertEquals(AgentWorkspaceScope.id("conversation", "session"), workspace)
        assertEquals(workspace, LocalModelAgentToolPolicy.workspace("conversation", "another-turn-session"))
        assertNotEquals(workspace, LocalModelAgentToolPolicy.workspace("other-conversation", "session"))
        assertNotEquals(LocalModelAgentToolPolicy.workspace("", "first"), LocalModelAgentToolPolicy.workspace("", "second"))
    }

    @Test fun compactDisclosureKeepsEveryToolIncludingTheTailAndProvidesARealInspectionContract() {
        val tools = listOf(AgentToolInspectionTools.definition().descriptor) + (0 until 250).map { descriptor(it) }
        val text = LocalModelAgentToolPolicy.disclosure(tools, 1000)
        tools.forEach { assertTrue("Missing disclosed ID: ${it.id}", text.contains("- ${it.id}:")) }
        assertTrue(text.contains("Contract inspection input:"))
        assertTrue(text.contains("schema_path"))
        assertFalse(text.contains("x".repeat(500)))
        assertTrue(text.length < 24_000)
    }

    @Test fun aScopedRegistryWithoutInspectionDoesNotAdvertiseAnUnavailableInspectionTool() {
        val descriptor = descriptor(1)
        val text = LocalModelAgentToolPolicy.disclosure(listOf(descriptor), 1)
        assertFalse(text.contains(AgentToolInspectionTools.DESCRIBE))
        assertTrue(text.contains(AgentNativeJsonCodec.stringify(descriptor.inputSchema.document)))
    }

    @Test fun detailedSchemasAreCompleteRatherThanCutIntoInvalidFragments() {
        val descriptor = descriptor(1)
        val text = LocalModelAgentToolPolicy.disclosure(listOf(descriptor), 100_000)
        assertTrue(text.contains(AgentNativeJsonCodec.stringify(descriptor.inputSchema.document)))
        assertTrue(LocalModelWebToolProtocol.systemPrompt(listOf(
            AgentToolInspectionTools.definition().descriptor, descriptor)).contains(descriptor.id))
    }

    private fun descriptor(index: Int) = AgentNativeToolDescriptor("public.tool.$index", "1.0.0", "Public tool $index",
        "Public contract", AgentNativeToolLocation.PHONE,
        AgentNativeJsonSchema.objectSchema(mapOf("value" to AgentNativeJsonSchema.string(description = "x".repeat(3000)))),
        AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)
}
