package com.galaxyssi.chat

/** Describes only tools in the invoking registry, including restricted registry views. */
internal object AgentToolInspectionTools {
    const val DESCRIBE = "galaxyssi.tools.describe"
    val toolIds = setOf(DESCRIBE, AgentToolDiscoveryTools.ID)

    fun definition() = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = DESCRIBE, version = "1.0.0", title = "Inspect a native tool contract",
            description = "Read a registered tool's contract even when it requires setup or is unavailable. " +
                "Inspection never executes or enables the target. The default schema_path is /input_schema; " +
                "use /description for usage or /availability for the current blocker.",
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "tool_id" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 160),
                "schema_path" to AgentNativeJsonSchema.string(maxLength = 1_024)),
                required = setOf("tool_id"), additionalProperties = false),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
            effect = AgentNativeToolEffect.READ_ONLY),
        executorId = "galaxyssi.tool_contract_inspection",
        executor = AgentNativeToolExecutor { invocation ->
            invocation.checkpoint()
            val id = invocation.input["tool_id"].toString()
            val tool = invocation.describeTool(id)
                ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "tool_not_disclosed", "This tool is not in the current registry view")
            val path = invocation.input["schema_path"]?.toString() ?: "/input_schema"
            val selected = runCatching { select(tool.catalogValue(), path) }
                .getOrElse { return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "schema_path_not_found", "Inspect a valid JSON Pointer in the disclosed tool contract") }
            AgentNativeToolExecutionResult.success(mapOf("tool_id" to id, "version" to tool.version,
                "schema_path" to path, "definition" to selected,
                "availability" to tool.catalogValue()["availability"], "target_executed" to false),
                "Tool contract inspected; no target operation executed")
        })

    internal fun select(document: AgentNativeJsonObject, path: String): Any? {
        if (path.isEmpty()) return document
        require(path.startsWith('/'))
        var current: Any? = document
        for (encoded in path.drop(1).split('/')) {
            require(!Regex("~(?![01])").containsMatchIn(encoded))
            val key = encoded.replace("~1", "/").replace("~0", "~")
            current = when (val value = current) {
                is Map<*, *> -> { require(value.containsKey(key)); value[key] }
                is List<*> -> { require(key == "0" || Regex("[1-9][0-9]*").matches(key)); value[key.toInt()] }
                else -> error("Not a container")
            }
        }
        return current
    }
}
