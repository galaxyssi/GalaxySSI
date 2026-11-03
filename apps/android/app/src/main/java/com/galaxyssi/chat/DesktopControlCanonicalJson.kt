package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

// Match Desktop's UTF-8 JSON contract; JSONObject.quote escapes slashes on Android.
internal fun desktopControlCanonicalJson(value: Any?): String = when (value) {
    null, JSONObject.NULL -> "null"
    is JSONObject -> value.keys().asSequence().sorted()
        .joinToString(",", "{", "}") { key ->
            "${desktopControlQuote(key)}:${desktopControlCanonicalJson(value.get(key))}"
        }
    is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") {
        desktopControlCanonicalJson(value.get(it))
    }
    is String -> desktopControlQuote(value)
    is Boolean, is Byte, is Short, is Int, is Long -> value.toString()
    is Float -> require(value.isFinite()).let { value.toString() }
    is Double -> require(value.isFinite()).let { value.toString() }
    else -> error("Unsupported Desktop control JSON value")
}

private fun desktopControlQuote(value: String): String = buildString(value.length + 2) {
    append('"')
    value.forEach { char ->
        when (char) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000c' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (char.code < 32) {
                append("\\u").append(char.code.toString(16).padStart(4, '0'))
            } else append(char)
        }
    }
    append('"')
}
