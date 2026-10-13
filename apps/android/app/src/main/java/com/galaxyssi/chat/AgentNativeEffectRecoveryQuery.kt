package com.galaxyssi.chat

import org.json.JSONObject

/** An observation recipe, never a retry command or a claim of business success. */
data class AgentNativeEffectRecoveryQuery private constructor(
    val toolId: String,
    val toolVersion: String,
    private val encodedArguments: String
) {
    constructor(toolId: String, toolVersion: String, arguments: AgentNativeJsonObject) :
        this(toolId, toolVersion, AgentNativeJsonCodec.stringify(arguments))

    init {
        require(toolId.isNotBlank() && toolVersion.isNotBlank()) { "Recovery query requires a tool contract" }
        require(AgentNativeJsonCodec.isCompatible(arguments)) { "Recovery arguments must be JSON-compatible" }
    }

    val arguments: AgentNativeJsonObject get() = JSONObject(encodedArguments).toNativeObject()

    fun toJsonValue(): AgentNativeJsonObject = mapOf(
        "format_version" to 1, "tool_id" to toolId, "tool_version" to toolVersion, "arguments" to arguments
    )

    companion object {
        internal fun fromJsonValue(value: Any?): AgentNativeEffectRecoveryQuery {
            val json = value as? Map<*, *> ?: error("Recovery query must be an object")
            require((json["format_version"] as? Number)?.toDouble() == 1.0) { "Unsupported recovery query format" }
            val arguments = json["arguments"] as? Map<*, *> ?: error("Recovery query arguments are missing")
            require(arguments.keys.all { it is String }) { "Recovery argument keys must be strings" }
            return AgentNativeEffectRecoveryQuery(
                json["tool_id"] as? String ?: error("Recovery tool is missing"),
                json["tool_version"] as? String ?: error("Recovery tool version is missing"),
                arguments.entries.associate { it.key as String to it.value }
            )
        }
    }
}

/** Pure metadata construction before dispatch; the model chooses whether/how to observe. */
fun interface AgentNativeEffectRecoveryProvider {
    fun queryFor(invocation: AgentNativeToolInvocation): AgentNativeEffectRecoveryQuery?
}
