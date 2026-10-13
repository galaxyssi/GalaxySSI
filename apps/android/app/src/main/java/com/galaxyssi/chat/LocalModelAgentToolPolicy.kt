package com.galaxyssi.chat

/** Ordinary local reasoning owns phone tools; research assignments retain their scoped evidence view. */
internal object LocalModelAgentToolPolicy {
    val toolIds: Set<String> by lazy {
        buildSet {
            addAll(LocalModelWebToolProtocol.toolIds)
            addAll(AgentToolInspectionTools.toolIds)
            addAll(AgentOnDeviceRuntimeTools.toolIds)
            addAll(AgentLinuxSoftwareNativeTools.toolIds)
            addAll(AgentPhoneNativeToolCatalog.toolIds.filter { it.startsWith("galaxyssi.workspace.") })
        }
    }

    fun toolIds(collaborationBound: Boolean, repairing: Boolean, interactiveBrowser: Boolean = false): Set<String> =
        if (collaborationBound) LocalModelWebToolProtocol.toolIds(true, repairing) +
            if (interactiveBrowser && !repairing) AgentInteractiveBrowserTools.toolIds + AgentToolInspectionTools.toolIds +
                setOf(AgentOnDeviceRuntimeTools.STATUS, AgentOnDeviceRuntimeTools.LIST_PACKS, AgentOnDeviceRuntimeTools.INSTALL_PACK) +
                AgentLinuxSoftwareNativeTools.toolIds else emptySet()
        else if (interactiveBrowser) toolIds + AgentInteractiveBrowserTools.toolIds else toolIds

    fun workspace(conversationId: String, sessionId: String) = AgentWorkspaceScope.id(conversationId, sessionId)

    /** Never cut the tail of a tool list or leave a schema truncated in the model's prompt. */
    fun disclosure(catalog: List<AgentNativeToolDescriptor>, schemaBudgetCharacters: Int = 18_000): String {
        require(schemaBudgetCharacters > 0)
        val canInspect = catalog.any { it.id == AgentToolInspectionTools.DESCRIBE }
        val detailed = StringBuilder()
        for (descriptor in catalog) {
            val schema = AgentNativeJsonCodec.stringify(descriptor.inputSchema.document)
            val line = "- ${descriptor.id}: ${descriptor.description.replace(Regex("\\s+"), " ")}; input=$schema\n"
            if (canInspect && detailed.length + line.length > schemaBudgetCharacters) return compact(catalog)
            detailed.append(line)
        }
        return detailed.toString()
    }

    private fun compact(catalog: List<AgentNativeToolDescriptor>): String = buildString {
        append("Compact catalog: all available IDs are listed below. Before using an unfamiliar input, call ")
        append(AgentToolInspectionTools.DESCRIBE)
        append(" with {\"tool_id\":\"the exact listed ID\"}; inspect /input_schema or /description. ")
        append("A missing inline schema does not mean the tool is unavailable.\n")
        if (catalog.any { it.id == AgentToolDiscoveryTools.ID }) {
            append("For capabilities absent from this available-tool list, use ")
            append(AgentToolDiscoveryTools.ID).append(" to discover registered tools and setup blockers.\n")
        }
        catalog.forEach { descriptor ->
            append("- ").append(descriptor.id).append(": ")
            append(descriptor.title.replace(Regex("\\s+"), " ").take(80)).append('\n')
        }
        catalog.firstOrNull { it.id == AgentToolInspectionTools.DESCRIBE }?.let {
            append("Contract inspection input: ").append(AgentNativeJsonCodec.stringify(it.inputSchema.document))
        }
    }
}
