package com.galaxyssi.chat

/** A view of the already-authorized catalog, not a separate execution allowlist. */
internal object AgentProgressiveToolCatalog {
    private val entryPoints = AgentWebIntelligenceNativeTools.directSearchToolIds + AgentToolInspectionTools.toolIds
    private const val SMALL_CATALOG = 12
    private const val RECENT_TOOLS = 4

    fun recent(history: List<AgentAction>): Set<String> = history.asReversed().asSequence()
        .filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL && it.status == AgentActionStatus.COMPLETED }
        .mapNotNull { action ->
            val id = action.parameters["tool_id"].orEmpty().ifBlank { action.target }
            if (id == AgentToolInspectionTools.DESCRIBE) {
                runCatching { org.json.JSONObject(action.parameters["input_json"].orEmpty()).getString("tool_id") }
                    .getOrNull()
            } else id
        }
        .filter { it.isNotBlank() && it !in entryPoints }.distinct().take(RECENT_TOOLS).toSet()

    fun render(eligible: List<AgentNativeToolDescriptor>, recent: Set<String>): String? {
        if (eligible.size <= SMALL_CATALOG ||
            !AgentToolInspectionTools.toolIds.all { id -> eligible.any { it.id == id } }) return null
        return buildString {
            val families = eligible.map { it.id.removePrefix("galaxyssi.").substringBefore('.') }.distinct().sorted()
            append("Available families: ").append(families.joinToString(", ")).append(".\n")
            append("Answer directly when no tool is needed. For other operations use tools.discover with a short capability or family; ")
            append("zero matches: rephrase or browse with an empty query and cursor. Use tools.describe for the exact contract. ")
            append("Only invoke available tools from this catalog or its discovery receipts. ! marks a required argument.\n")
            for (tool in eligible) {
                if (tool.id !in entryPoints && tool.id !in recent) continue
                append("- ").append(tool.id).append(" | risk=").append(tool.risk.wireValue)
                if (tool.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY) append(" | concurrency=parallel_read_only")
                append(" | input=").append(signature(tool.inputSchema.document)).append('\n')
            }
        }
    }

    private fun signature(schema: AgentNativeJsonObject): String {
        val required = schema["required"] as? Collection<*> ?: emptyList<Any?>()
        val fields = schema["properties"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        return fields.entries.joinToString(",", "{", "}") { (name, definition) ->
            val field = definition as? Map<*, *>
            val choices = field?.get("enum") as? Collection<*>
            val type = when {
                choices != null && choices.size in 1..5 -> choices.joinToString("|")
                field?.get("type") == "array" -> "list<" + ((field["items"] as? Map<*, *>)?.get("type") ?: "any") + ">"
                else -> field?.get("type")?.toString() ?: "any"
            }
            "$name${if (name in required) "!" else ""}:$type"
        }
    }
}
