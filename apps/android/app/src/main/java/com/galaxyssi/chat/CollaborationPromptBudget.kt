package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Required instructions are atomic; optional evidence is omitted as a whole, never silently clipped. */
internal object CollaborationPromptBudget {
    data class Section(val name: String, val content: String, val recall: String = "")
    data class Result(val text: String, val included: Set<String>, val omitted: Set<String>)

    fun assemble(required: List<Section>, optional: List<Section>, maxChars: Int): Result {
        require(maxChars > 0)
        val sections = required + optional
        require(sections.all { it.name.isNotBlank() && it.name.length <= 120 && it.recall.length <= 512 })
        require(sections.map { it.name }.distinct().size == sections.size) { "Prompt section identities must be unique" }
        val included = linkedSetOf<String>()
        val omitted = linkedSetOf<String>()
        val text = StringBuilder()
        required.forEach { section ->
            text.append(render(section))
            included += section.name
        }
        val reserve = omissionNote(optional.sortedByDescending { reference(it).toString().length }).length
        require(text.length + reserve <= maxChars) {
            "Required assignment/contract exceeds the dispatch context; publish a durable reference before dispatch, never truncate instructions"
        }
        optional.forEach { section ->
            val rendered = render(section)
            if (text.length + rendered.length + reserve <= maxChars) {
                text.append(rendered)
                included += section.name
            } else omitted += section.name
        }
        if (omitted.isNotEmpty()) text.append(omissionNote(optional.filter { it.name in omitted }))
        check(text.length <= maxChars)
        return Result(text.toString(), included, omitted)
    }

    private fun render(section: Section) = "\n[${section.name}]\n${section.content}\n"

    private fun omissionNote(sections: List<Section>): String {
        if (sections.isEmpty()) return ""
        val references = JSONArray()
        sections.take(8).forEach { section ->
            references.put(reference(section))
        }
        return "\n[Context coverage]\n" + JSONObject().put("omitted_sections", sections.size)
            .put("references", references).put("unlisted_references", (sections.size - references.length()).coerceAtLeast(0))
            .put("instruction", "The omitted evidence remains outside this prompt. Retrieve relevant originals before relying on them; do not claim complete review from this excerpt.") + "\n"
    }

    private fun reference(section: Section) = JSONObject().put("section", section.name)
        .put("characters", section.content.length).put("recall", section.recall)
}
