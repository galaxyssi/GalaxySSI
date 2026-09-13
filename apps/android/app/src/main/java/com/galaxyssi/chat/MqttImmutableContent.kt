package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

internal object MqttImmutableContent {
    const val RECORD_KEY = "_link_rx_key"
    fun hash(value: JSONObject): String = sha256(canonical(value))
    fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    private fun canonical(value: Any?, depth: Int = 0): String {
        require(depth <= 64) { "Inbound JSON nesting exceeds limit" }
        return when (value) {
            null, JSONObject.NULL -> "null"
            is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") {
                JSONObject.quote(it) + ":" + canonical(value.get(it), depth + 1)
            }
            is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it), depth + 1) }
            is String -> JSONObject.quote(value)
            is Boolean -> value.toString()
            is Number -> JSONObject.numberToString(value)
            else -> error("Unsupported inbound JSON value")
        }
    }
}
