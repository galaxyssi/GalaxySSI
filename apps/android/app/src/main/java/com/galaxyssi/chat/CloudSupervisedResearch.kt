package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Public retrieval stays in the model's tool loop; device mutations stay in the phone kernel. */
internal object CloudSupervisedResearch {
    private val tools = setOf("web_search", "web_image_search", "web_fetch", "web_extract", "web_weather")

    fun permits(name: String): Boolean = name in tools

    fun install(prepared: PreparedCloudConversationStream) {
        val definitions = CloudWebGrounding.openAiTools()
        val functions = (0 until definitions.length()).map { definitions.getJSONObject(it).getJSONObject("function") }
            .filter { permits(it.getString("name")) }
        when (prepared.provider) {
            com.galaxyssi.chat.voice.modelstream.ModelStreamProvider.ANTHROPIC ->
                prepared.body.put("tools", JSONArray(functions.map { function ->
                    JSONObject().put("name", function.getString("name"))
                        .put("description", function.getString("description"))
                        .put("input_schema", function.getJSONObject("parameters"))
                }))
            com.galaxyssi.chat.voice.modelstream.ModelStreamProvider.GEMINI ->
                prepared.body.put("tools", JSONArray().put(JSONObject().put("functionDeclarations", JSONArray(functions))))
            else -> prepared.body.put("tools", JSONArray(functions.map {
                JSONObject().put("type", "function").put("function", it)
            })).put("tool_choice", "auto")
        }
    }

    const val INSTRUCTION = "Public research functions web_search, web_image_search, web_fetch, web_extract and web_weather " +
        "are directly callable in this model turn and run on the phone. Use their API tool schemas, not DSML/XML " +
        "or a CALL_NATIVE_TOOL plan for the same public retrieval. Their observations remain in this conversation. " +
        "For an ordinary lookup start with a focused fast search; read_pages=true can retrieve source bodies " +
        "in the same call. Search further only for a specific material gap in the user's request. Do not " +
        "restart successful searches because an optional source is inaccessible. Summarize supported facts " +
        "and clearly qualify uncertainty instead of endlessly collecting sources. Once sufficient, return " +
        "the completion-only phone ActionPlan with the actual answer and observed source links in " +
        "task-complete.description. For device operations, files, login or other actions, return the phone " +
        "ActionPlan using the supplied native tool inventory and wait for execution receipts. Public web " +
        "retrieval cannot substitute for phone side effects. Never execute on Desktop."
}
