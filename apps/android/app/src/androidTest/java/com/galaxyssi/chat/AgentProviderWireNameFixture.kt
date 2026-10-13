package com.galaxyssi.chat

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject

/** Checks typed SDK name fields only; fixture data and tool arguments are not transport names. */
internal object AgentProviderWireNameFixture {
    fun enforce(server: MockWebServer, style: String) {
        val queued = server.dispatcher
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val valid = runCatching {
                    allNames(style, JSONObject(request.body.clone().readUtf8())).all { SAFE_NAME.matches(it) }
                }.getOrDefault(false)
                return if (valid) queued.dispatch(request) else MockResponse().setResponseCode(400)
                    .setBody("{\"error\":\"Invalid public fixture function name\"}")
            }
            override fun shutdown() = queued.shutdown()
        }
    }

    fun declarations(style: String, body: JSONObject): List<String> {
        val tools = body.getJSONArray("tools")
        return when (style) {
            "gemini" -> objects(tools).flatMap { objects(it.getJSONArray("functionDeclarations")) }.map { it.getString("name") }
            "anthropic" -> objects(tools).map { it.getString("name") }
            else -> objects(tools).map { it.getJSONObject("function").getString("name") }
        }
    }

    fun historicalCalls(style: String, body: JSONObject): List<String> = when (style) {
        "gemini" -> objects(body.getJSONArray("contents")).flatMap { objects(it.getJSONArray("parts")) }
            .mapNotNull { it.optJSONObject("functionCall")?.getString("name") }
        "anthropic" -> objects(body.getJSONArray("messages")).flatMap { objects(it.optJSONArray("content")) }
            .filter { it.optString("type") == "tool_use" }.map { it.getString("name") }
        else -> objects(body.getJSONArray("messages")).flatMap { objects(it.optJSONArray("tool_calls")) }
            .map { it.getJSONObject("function").getString("name") }
    }

    private fun allNames(style: String, body: JSONObject): List<String> {
        val replies = if (style == "gemini") objects(body.getJSONArray("contents"))
            .flatMap { objects(it.getJSONArray("parts")) }
            .mapNotNull { it.optJSONObject("functionResponse")?.getString("name") } else emptyList()
        return declarations(style, body) + historicalCalls(style, body) + replies
    }

    private fun objects(array: JSONArray?): List<JSONObject> = if (array == null) emptyList() else
        (0 until array.length()).mapNotNull { array.optJSONObject(it) }

    private val SAFE_NAME = Regex("[a-zA-Z0-9_-]{1,64}")
}
