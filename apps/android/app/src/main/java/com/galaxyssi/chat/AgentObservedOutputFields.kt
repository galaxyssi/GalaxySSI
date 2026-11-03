package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A bounded navigation aid, never completion evidence or an automatic field substitution. */
internal object AgentObservedOutputFields {
    data class Index(val fields: Map<String, String>, val partial: Boolean)

    fun output(action: AgentAction): JSONObject? = runCatching {
        val raw = JSONObject(action.evidence)
        raw.optJSONObject("output") ?: raw
    }.getOrNull()

    fun at(root: JSONObject, pointer: String): Any? {
        var value: Any? = root
        for (part in pointer.removePrefix("/").split('/')) {
            val key = part.replace("~1", "/").replace("~0", "~")
            value = when (val current = value) {
                is JSONObject -> current.opt(key)
                is JSONArray -> key.toIntOrNull()?.let(current::opt)
                else -> null
            }
        }
        return value?.takeUnless { it == JSONObject.NULL }
    }

    fun index(output: JSONObject): Index {
        val fields = linkedMapOf<String, String>()
        var visited = 0
        var partial = false
        fun visit(value: Any?, path: String, depth: Int) {
            if (++visited > 512 || depth > 12 || fields.size >= 96) {
                partial = true
                return
            }
            when (value) {
                is JSONObject -> {
                    val keys = value.keys()
                    while (keys.hasNext()) {
                        if (visited >= 512 || fields.size >= 96) { partial = true; break }
                        val key = keys.next()
                        val next = "$path/${key.replace("~", "~0").replace("/", "~1")}"
                        if (AgentObservedOutcome.validPath(next)) visit(value.opt(key), next, depth + 1)
                        else partial = true
                    }
                }
                is JSONArray -> for (i in 0 until value.length()) {
                    if (visited >= 512 || fields.size >= 96) { partial = true; break }
                    visit(value.opt(i), "$path/$i", depth + 1)
                }
                is String -> fields[path] = "string"
                is Boolean -> fields[path] = "boolean"
                is Number -> fields[path] = "number"
                else -> if (path.isNotEmpty()) fields[path] = "null"
            }
        }
        visit(output, "", 0)
        return Index(fields, partial)
    }

    fun promptIndex(action: AgentAction, maximumCharacters: Int = 1_200): String? {
        if (action.kind != AgentActionKind.CALL_NATIVE_TOOL || action.status != AgentActionStatus.COMPLETED) return null
        val index = index(output(action) ?: return null)
        if (index.fields.isEmpty()) return null
        val fields = JSONObject()
        val envelope = JSONObject().put("fields", fields).put("partial", index.partial)
        for ((path, type) in index.fields) {
            fields.put(path, type)
            if (envelope.toString().length > maximumCharacters) {
                fields.remove(path)
                envelope.put("partial", true)
                break
            }
        }
        return envelope.toString().takeIf { fields.length() > 0 && it.length <= maximumCharacters }
    }

    fun alternatives(index: Index, path: String): List<String> = index.fields.keys.asSequence()
        .filter { it != path && it.substringAfterLast('/') == path.substringAfterLast('/') }
        .take(4).toList()
}
