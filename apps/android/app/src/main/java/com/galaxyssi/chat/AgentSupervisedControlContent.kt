package com.galaxyssi.chat

import org.json.JSONObject

/** Recognizes provider control syntax without confusing ordinary prose with a tool request. */
internal object AgentSupervisedControlContent {
    fun hasToolMarkup(text: String): Boolean = TOOL_MARKUP.containsMatchIn(text)

    fun hasControlFields(json: JSONObject): Boolean = CONTROL_FIELDS.any(json::has)

    fun isProtocol(text: String): Boolean = hasToolMarkup(text) ||
        (CONTROL_FIELD.containsMatchIn(text) &&
            AgentExecutionSiteDecisionCodec.extractJsonObject(text)?.let(::hasControlFields) == true)

    const val REPAIR_REASON = "inline_tool_protocol: The response contains unexecuted tool instructions, " +
        "not a final answer. No tool in that response has run. Convert the intended calls and their " +
        "arguments to the supplied JSON ActionPlan with execution_location=phone and CALL_NATIVE_TOOL " +
        "actions. Use exact available tool IDs. Do not emit DSML/XML, claim execution, or replace the " +
        "missing observations with a prose answer. Wait for Android tool receipts before answering."

    private val CONTROL_FIELDS = setOf("execution_location", "actions", "action", "tool_calls", "function_call")
    private val CONTROL_FIELD = Regex("\"(?:execution_location|actions?|tool_calls|function_call)\"\\s*:")
    private val TOOL_MARKUP = Regex(
        "<\\s*[/|\uFF5C\\s]*(?:DSML|tool_calls?|function_calls?|invoke)(?=\\b|[|\uFF5C])",
        RegexOption.IGNORE_CASE
    )
}
