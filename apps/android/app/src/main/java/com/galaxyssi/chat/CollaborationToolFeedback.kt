package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

/** Observable validation facts, not a retry policy or a model-authored root-cause diagnosis. */
internal object CollaborationToolFeedback {
    class Invalid(val problem: JSONObject, message: String) : IllegalArgumentException(message)

    fun reject(code: String, path: String, message: String, expected: Any? = null, actual: Any? = null): Nothing =
        throw Invalid(problem(code, path, expected, actual), message)

    fun require(condition: Boolean, code: String, path: String, message: String, expected: Any? = null, actual: Any? = null) {
        if (!condition) reject(code, path, message, expected, actual)
    }

    fun parse(stdout: String): JSONObject {
        val parsed = try {
            val tokens = JSONTokener(stdout)
            val value = tokens.nextValue()
            require(tokens.nextClean() == '\u0000', "report_trailing_content", "",
                "Tool stdout contains content after the JSON value", "one complete JSON object", "trailing content")
            value
        } catch (error: JSONException) {
            val message = error.message.orEmpty()
            reject("report_json_unparseable", "", "Captured tool stdout could not be parsed", "one complete JSON object",
                JSONObject().put("parser_message", message.take(256)).put("parser_message_truncated", message.length > 256))
        }
        require(parsed is JSONObject, "report_object_required", "", "Tool report must be an object", "object", type(parsed))
        return parsed as JSONObject
    }

    fun failed(error: Throwable) = JSONObject().put("passed", false)
        .put("diagnosis", error.message ?: "Tool report validation failed")
        .put("problems", JSONArray().put((error as? Invalid)?.problem
            ?: problem("tool_report_invalid", "", actual = error.javaClass.simpleName)))

    fun problem(code: String, path: String, expected: Any? = null, actual: Any? = null): JSONObject =
        JSONObject().put("code", code).put("path", path).put("expected", expected ?: JSONObject.NULL)
            .put("actual", actual ?: JSONObject.NULL).put("cause", "not_diagnosed")

    // Keep full expected/actual values in the parent check; return the first exact JSON Pointer here.
    fun difference(expected: Any, actual: Any, path: String = ""): JSONObject? {
        if (expected is Number && actual is Number) {
            if (expected.toString().toBigDecimal().compareTo(actual.toString().toBigDecimal()) == 0) return null
        } else if (expected is JSONObject && actual is JSONObject) {
            val expectedKeys = expected.keys().asSequence().toSet()
            val actualKeys = actual.keys().asSequence().toSet()
            for (key in (expectedKeys + actualKeys).sorted()) {
                val child = "$path/${key.replace("~", "~0").replace("/", "~1")}"
                if (key !in actualKeys) return problem("missing_key", child, "present", "absent")
                if (key !in expectedKeys) return problem("unexpected_key", child, "absent", "present")
                difference(expected.get(key), actual.get(key), child)?.let { return it }
            }
            return null
        } else if (expected is JSONArray && actual is JSONArray) {
            if (expected.length() != actual.length()) return problem("array_length_mismatch", path, expected.length(), actual.length())
            repeat(expected.length()) { index -> difference(expected.get(index), actual.get(index), "$path/$index")?.let { return it } }
            return null
        } else if (expected == actual) return null
        return problem(if (type(expected) == type(actual)) "value_mismatch" else "type_mismatch", path, type(expected), type(actual))
    }

    private fun type(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> "object"
        is JSONArray -> "array"
        is Number -> "number"
        is Boolean -> "boolean"
        is String -> "string"
        else -> "unknown"
    }
}
