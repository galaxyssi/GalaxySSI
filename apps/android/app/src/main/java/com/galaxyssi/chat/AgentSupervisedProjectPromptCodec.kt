package com.galaxyssi.chat

internal object AgentSupervisedProjectPromptCodec {
    const val DYNAMIC_CONTEXT_HEADER = "Current phone project context:\n"

    fun compactInputSchema(document: AgentNativeJsonObject, maximumCharacters: Int): String =
        schemaShape(document, depth = 0)
            .take(maximumCharacters.coerceAtLeast(MINIMUM_SCHEMA_CHARACTERS))

    fun preserveToolInventory(prompt: String, maximumCharacters: Int): String {
        val limit = maximumCharacters.coerceAtLeast(MINIMUM_PROMPT_CHARACTERS)
        if (prompt.length <= limit) return prompt
        val toolsAt = prompt.indexOf(TOOLS_HEADER)
        if (toolsAt < 0) return compactMiddle(prompt, limit)
        val dynamicAt = prompt.indexOf(DYNAMIC_CONTEXT_HEADER, startIndex = toolsAt + TOOLS_HEADER.length)
        if (dynamicAt >= 0) {
            return preserveCacheablePrefix(
                contract = prompt.substring(0, toolsAt),
                tools = prompt.substring(toolsAt, dynamicAt),
                dynamic = prompt.substring(dynamicAt),
                limit = limit
            )
        }
        val tools = prompt.substring(toolsAt)
        val prefix = prompt.substring(0, toolsAt)
        if (tools.length >= limit) return compactMiddle(tools, limit)
        preserveConversationTransport(prefix, tools, limit)?.let { return it }
        val prefixBudget = limit - tools.length
        return compactMiddle(prefix, prefixBudget).trimEnd() + '\n' + tools
    }

    private fun preserveCacheablePrefix(
        contract: String,
        tools: String,
        dynamic: String,
        limit: Int
    ): String {
        val dynamicReserve = minOf(
            dynamic.length,
            MINIMUM_DYNAMIC_CONTEXT_CHARACTERS.coerceAtMost(limit / 3)
        )
        val stableBudget = (limit - dynamicReserve).coerceAtLeast(tools.length)
        val stable = if (contract.length + tools.length <= stableBudget) {
            contract + tools
        } else {
            val contractBudget = (stableBudget - tools.length).coerceAtLeast(0)
            compactMiddle(contract, contractBudget).trimEnd() + '\n' + tools
        }
        val dynamicBudget = (limit - stable.length).coerceAtLeast(0)
        val compactDynamic = when {
            dynamic.length <= dynamicBudget -> dynamic
            dynamicBudget <= 0 -> ""
            else -> preserveConversationTransport(dynamic, tools = "", limit = dynamicBudget)
                ?: compactMiddle(dynamic, dynamicBudget)
        }
        return (stable + compactDynamic).take(limit)
    }

    private fun preserveConversationTransport(prefix: String, tools: String, limit: Int): String? {
        val contextAt = prefix.indexOf(AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_HEADER)
        if (contextAt < 0) return null
        val footerAt = prefix.indexOf(
            AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_FOOTER,
            startIndex = contextAt
        )
        if (footerAt < 0) return null
        val contextEnd = footerAt + AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_FOOTER.length
        val contractAndGoal = prefix.substring(0, contextAt)
        val conversation = prefix.substring(contextAt, contextEnd)
        val evidence = prefix.substring(contextEnd)
        val dynamicBudget = limit - tools.length - conversation.length - SECTION_SEPARATOR.length * 3
        if (dynamicBudget <= MINIMUM_REQUIRED_DYNAMIC_CHARACTERS) return null

        val evidenceBudget = minOf(
            evidence.length,
            maxOf(MINIMUM_EVIDENCE_CHARACTERS, dynamicBudget / 4)
        )
        val contractBudget = dynamicBudget - evidenceBudget
        if (contractBudget <= 0) return null
        return buildString(limit) {
            append(compactMiddle(contractAndGoal, contractBudget).trimEnd())
            append(SECTION_SEPARATOR)
            append(conversation.trim())
            append(SECTION_SEPARATOR)
            append(compactMiddle(evidence, evidenceBudget).trim())
            append(SECTION_SEPARATOR)
            append(tools)
        }.take(limit)
    }

    private fun schemaShape(schema: Map<String, Any?>, depth: Int): String {
        val type = schema["type"]?.toString().orEmpty()
        return when (type) {
            "object" -> objectShape(schema, depth)
            "array" -> {
                val items = schema["items"] as? Map<*, *>
                val itemShape = items?.toStringKeyMap()?.let { schemaShape(it, depth + 1) } ?: "any"
                "[$itemShape]"
            }
            "string" -> enumShape(schema) ?: "string"
            "integer" -> "int"
            "number" -> "number"
            "boolean" -> "bool"
            "null" -> "null"
            else -> type.ifBlank { "any" }
        }
    }

    private fun objectShape(schema: Map<String, Any?>, depth: Int): String {
        val properties = (schema["properties"] as? Map<*, *>)?.toStringKeyMap().orEmpty()
        if (properties.isEmpty()) return if (schema["additionalProperties"] == false) "{}" else "{...}"
        val required = (schema["required"] as? Collection<*>)
            .orEmpty()
            .mapNotNull { it?.toString() }
            .toSet()
        val fields = properties.entries.joinToString(",") { (name, rawSchema) ->
            val nested = rawSchema as? Map<*, *>
            val shape = if (nested == null) {
                "any"
            } else if (depth >= MAX_SCHEMA_DEPTH) {
                nested["type"]?.toString().orEmpty().ifBlank { "any" }
            } else {
                schemaShape(nested.toStringKeyMap(), depth + 1)
            }
            "$name${if (name in required) "!" else ""}:$shape"
        }
        return "{$fields}"
    }

    private fun enumShape(schema: Map<String, Any?>): String? {
        val values = (schema["enum"] as? Collection<*>)
            .orEmpty()
            .mapNotNull { it?.toString()?.takeIf(String::isNotBlank) }
            .take(MAX_ENUM_VALUES)
        return values.takeIf(List<String>::isNotEmpty)?.joinToString("|", "string(", ")")
    }

    private fun compactMiddle(value: String, maximumCharacters: Int): String {
        if (value.length <= maximumCharacters) return value
        if (maximumCharacters <= COMPACTION_MARKER.length + 2) return value.take(maximumCharacters)
        val remaining = maximumCharacters - COMPACTION_MARKER.length
        val head = remaining / 2
        val tail = remaining - head
        return value.take(head).trimEnd() + COMPACTION_MARKER + value.takeLast(tail).trimStart()
    }

    private fun Map<*, *>.toStringKeyMap(): Map<String, Any?> = entries.associate { entry ->
        entry.key.toString() to entry.value
    }

    private const val TOOLS_HEADER = "Available phone tools:\n"
    private const val COMPACTION_MARKER = "\n[Earlier prompt context compacted]\n"
    private const val SECTION_SEPARATOR = "\n"
    private const val MINIMUM_SCHEMA_CHARACTERS = 48
    private const val MINIMUM_PROMPT_CHARACTERS = 4_000
    private const val MINIMUM_REQUIRED_DYNAMIC_CHARACTERS = 1_000
    private const val MINIMUM_EVIDENCE_CHARACTERS = 1_200
    private const val MINIMUM_DYNAMIC_CONTEXT_CHARACTERS = 4_000
    private const val MAX_SCHEMA_DEPTH = 2
    private const val MAX_ENUM_VALUES = 8
}
