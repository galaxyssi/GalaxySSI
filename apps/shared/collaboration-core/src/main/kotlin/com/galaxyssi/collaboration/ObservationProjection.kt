package com.galaxyssi.collaboration

import org.json.JSONArray
import org.json.JSONObject

/** Select data from an original tool envelope without treating strings as instructions. */
object ObservationProjection {
    fun select(output: JSONObject, reportPointer: String, pointer: String): Any {
        val selected = at(output, reportPointer)
        val report = when (selected) {
            is JSONObject -> selected
            is String -> JSONObject(selected)
            else -> throw IllegalArgumentException("Observation report must be a JSON object or encoded JSON object")
        }
        return at(report, pointer)
    }

    private fun at(root: JSONObject, pointer: String): Any {
        if (pointer.isEmpty()) return root
        require(pointer.startsWith('/') && !Regex("~(?![01])").containsMatchIn(pointer)) { "Invalid observation JSON pointer" }
        return pointer.drop(1).split('/').fold(root as Any) { value, segment ->
            val key = segment.replace("~1", "/").replace("~0", "~")
            when (value) {
                is JSONObject -> value.get(key)
                is JSONArray -> {
                    require(key.matches(Regex("0|[1-9][0-9]*"))) { "Invalid observation array index" }
                    value.get(key.toInt())
                }
                else -> throw IllegalArgumentException("Observation pointer traverses a non-container")
            }
        }
    }
}
