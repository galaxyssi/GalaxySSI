package com.galaxyssi.chat

import java.util.Base64
import java.util.Locale
import org.json.JSONObject

/** Bounded metadata discovery within the invoking registry; no target setup or execution. */
internal object AgentToolDiscoveryTools {
    const val ID = "galaxyssi.tools.discover"

    fun definition() = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = ID, version = "1.0.0", title = "Discover registered capabilities and setup blockers",
            description = "Search registered tool IDs, titles and descriptions, including unavailable tools. " +
                "Read the exact contract with galaxyssi.tools.describe before correcting an operation. " +
                "Follow next_cursor with the same query; discovery does not install dependencies or execute tools.",
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "query" to AgentNativeJsonSchema.string(maxLength = 256),
                "cursor" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 1024),
                "limit" to AgentNativeJsonSchema.integer(minimum = 1, maximum = 50)), additionalProperties = false),
            outputSchema = AgentNativeJsonSchema.objectSchema(), risk = AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
            effect = AgentNativeToolEffect.READ_ONLY),
        executorId = "galaxyssi.tool_capability_discovery",
        executor = AgentNativeToolExecutor { invocation ->
            invocation.checkpoint()
            page(invocation.discoverTools(), invocation.input)
        })

    internal fun page(catalog: List<AgentNativeToolDescriptor>, input: AgentNativeJsonObject): AgentNativeToolExecutionResult {
        val query = input["query"]?.toString().orEmpty().trim().lowercase(Locale.ROOT)
        val queryHash = AgentNativeJsonCodec.sha256(query)
        val tools = catalog.sortedBy { it.id }
        val revision = AgentNativeJsonCodec.sha256(tools.map { descriptor ->
            descriptor.catalogValue() + mapOf("availability" to mapOf(
                "status" to descriptor.availability.status.wireValue, "reason" to descriptor.availability.reason))
        })
        val cursor = input["cursor"]?.toString()?.let { encoded ->
            runCatching {
                require(encoded.length <= 1024)
                val value = JSONObject(String(Base64.getUrlDecoder().decode(encoded), Charsets.UTF_8))
                require(value.getString("query_sha256") == queryHash)
                require(value.getString("revision").matches(Regex("[a-f0-9]{64}")))
                require(value.getString("after_id").isNotBlank())
                value
            }.getOrElse { return failure("tool_discovery_cursor_invalid", "Use the returned cursor with its original query.") }
        }
        if (cursor != null && cursor.optString("revision") != revision) return failure(
            "tool_catalog_changed", "Registered capability metadata changed. Restart discovery without a cursor.")
        val after = cursor?.optString("after_id").orEmpty()
        val words = query.split(Regex("\\s+")).filter(String::isNotEmpty)
        val matches = tools.filter { descriptor ->
            val text = "${descriptor.id} ${descriptor.title} ${descriptor.description}".lowercase(Locale.ROOT)
            words.all(text::contains)
        }
        if (after.isNotEmpty() && matches.none { it.id == after }) return failure(
            "tool_discovery_cursor_invalid", "The cursor does not refer to this capability search.")
        val limit = (input["limit"] as? Number)?.toInt()?.coerceIn(1, 50) ?: 20
        val remaining = matches.dropWhile { it.id <= after }
        val selected = remaining.take(limit)
        val output = linkedMapOf<String, Any?>(
            "catalog_sha256" to revision, "query" to query, "total_matches" to matches.size,
            "contract_tool_id" to AgentToolInspectionTools.DESCRIBE, "target_executed" to false,
            "tools" to selected.map { descriptor -> mapOf(
                "id" to descriptor.id, "version" to descriptor.version, "title" to descriptor.title,
                "description" to descriptor.description.take(400),
                "description_truncated" to (descriptor.description.length > 400),
                "availability" to mapOf("status" to descriptor.availability.status.wireValue,
                    "reason" to descriptor.availability.reason)) }
        )
        if (remaining.size > selected.size) output["next_cursor"] = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(AgentNativeJsonCodec.stringify(mapOf("revision" to revision,
                "query_sha256" to queryHash, "after_id" to selected.last().id)).toByteArray(Charsets.UTF_8))
        return AgentNativeToolExecutionResult.success(output, "Registered capability metadata observed; no target executed")
    }

    private fun failure(code: String, message: String) = AgentNativeToolExecutionResult.failure(code, message,
        details = mapOf("executed" to false, "goal_terminal" to false))
}
