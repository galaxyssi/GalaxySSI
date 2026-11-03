package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Section ranges index immutable pages, not a second copy or summary of their contents. */
internal object CollaborationGoalContractSections {
    fun valid(section: String) = section.length <= 512 &&
        (section in setOf("goal", "criteria", "source") ||
            section.startsWith("context:") && section.removePrefix("context:").isNotBlank())

    fun key(section: String) = AgentResultRecoveryClient.sha256(section.toByteArray(Charsets.UTF_8))

    fun index(pages: List<String>): JSONObject {
        val names = mutableMapOf<Int, StringBuilder>()
        val ranges = linkedMapOf<String, IntRange>()
        fun include(name: String, page: Int) {
            ranges[name] = (ranges[name]?.first ?: page)..page
        }
        pages.forEachIndexed { page, raw ->
            val fragments = JSONObject(raw).getJSONArray("fragments")
            repeat(fragments.length()) { i ->
                val fragment = fragments.getJSONObject(i)
                when (val stream = fragment.getString("stream")) {
                    "goal", "criteria", "source" -> include(stream, page)
                    "context", "context_name" -> {
                        val index = fragment.getInt("context_index")
                        if (stream == "context_name") names.getOrPut(index) { StringBuilder() }.append(fragment.getString("text"))
                        else if (!fragment.isNull("id")) names[index] = StringBuilder(fragment.getString("id"))
                        include("context_index:$index", page)
                    }
                }
            }
        }
        return JSONObject().apply {
            ranges.forEach { (name, range) ->
                val section = if (name.startsWith("context_index:"))
                    "context:" + requireNotNull(names[name.substringAfter(':').toInt()]).toString() else name
                put(key(section), JSONArray(listOf(range.first, range.last)))
            }
        }
    }
}
