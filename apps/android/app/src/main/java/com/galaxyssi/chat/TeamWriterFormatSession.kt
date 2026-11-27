package com.galaxyssi.chat

import java.net.URI
import org.json.JSONArray
import org.json.JSONObject

internal fun canonicalTeamLoopback(endpoint: String): URI? = runCatching { URI(endpoint) }.getOrNull()?.takeIf {
    it.scheme in setOf("http", "https") && it.host in setOf("127.0.0.1", "[::1]") &&
        it.rawUserInfo == null && it.rawQuery == null && it.rawFragment == null &&
        it.rawPath == "/v1/chat/completions" && (it.port == -1 || it.port in 1..65535) &&
        !it.rawAuthority.endsWith(':')
}

/** A successful plan may advertise a local decoder. Never share its capability with a second team run. */
internal class TeamWriterFormatSession {
    @Volatile private var confirmed: URI? = null

    fun observe(endpoint: String, responseUrl: String, server: String?) {
        confirmed = canonicalTeamLoopback(endpoint)?.takeIf {
            it == canonicalTeamLoopback(responseUrl) && server != null && llamaServer.matches(server.trim())
        }
    }

    fun format(system: String, endpoint: String, stage: String): JSONObject? {
        val known = confirmed ?: return null
        if (system != contrastWriterSystem || stage !in setOf("synthesis", "rewrite") ||
            known != canonicalTeamLoopback(endpoint)) return null
        val text = JSONObject().put("type", "string")
        val direction = JSONObject().put("type", "string").put("enum", JSONArray(listOf("higher", "lower")))
        fun record(vararg fields: Pair<String, JSONObject>): JSONObject {
            val properties = JSONObject()
            fields.forEach { (name, value) -> properties.put(name, value) }
            return JSONObject().put("type", "object").put("properties", properties)
                .put("required", JSONArray(fields.map { it.first })).put("additionalProperties", false)
        }
        val claim = record("purpose" to text, "input" to text, "input_direction" to direction,
            "readout" to text, "expected_direction" to direction, "alternative" to text, "gap" to text)
        val schema = if (stage == "rewrite") claim else
            JSONObject().put("anyOf", JSONArray().put(claim).put(record("answer" to text)))
        return JSONObject().put("type", "json_schema").put("json_schema",
            JSONObject().put("name", "team_prediction").put("strict", true).put("schema", schema))
    }

    private companion object {
        val llamaServer = Regex("""llama\.cpp(?:/[A-Za-z0-9._-]+)?""", RegexOption.IGNORE_CASE)
    }
}
