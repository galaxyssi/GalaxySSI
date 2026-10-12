package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Required instructions are atomic; optional evidence is omitted as a whole, never silently clipped. */
internal object CollaborationPromptBudget {
    private const val FAILURE_CODE = "host_dispatch_context_overflow: "
    private const val LEGACY_FAILURE = "Required assignment/contract exceeds the dispatch context; publish a durable reference before dispatch, never truncate instructions"
    data class Section(val name: String, val content: String, val recall: String = "")
    data class Result(val text: String, val included: Set<String>, val omitted: Set<String>)

    class Overflow(required: List<Section>, reserve: Int, maxChars: Int) : IllegalArgumentException(
        FAILURE_CODE + JSONObject().put("component", "CollaborationPromptBudget").put("model_dispatched", false)
            .put("required_characters", required.sumOf(::renderedLength)).put("reference_characters", reserve)
            .put("max_characters", maxChars).put("sections", JSONObject().apply {
                required.forEach { put(it.name, renderedLength(it)) }
            }) + ". Restore a fitting durable reference before dispatch; never truncate instructions. " +
            "No model answer exists to repair. Preserve this checkpoint until host context preparation is repaired, then resume."
    )

    fun failure(result: AgentSubagentChildResult?): String = result?.takeIf {
        it.status == AgentSubagentStatus.FAILED && it.output.isBlank() &&
            (it.errorMessage.startsWith(FAILURE_CODE) || it.errorMessage == LEGACY_FAILURE)
    }?.errorMessage.orEmpty()

    fun assemble(required: List<Section>, optional: List<Section>, maxChars: Int,
                 presentationOrder: List<String> = emptyList()): Result {
        require(maxChars > 0)
        val sections = required + optional
        require(sections.all { it.name.isNotBlank() && it.name.length <= 120 && it.recall.length <= 512 })
        require(sections.map { it.name }.distinct().size == sections.size) { "Prompt section identities must be unique" }
        require(presentationOrder.distinct().size == presentationOrder.size &&
            presentationOrder.all { name -> sections.any { it.name == name } }) { "Presentation order must name distinct known sections" }
        val included = linkedSetOf<String>()
        val omitted = linkedSetOf<String>()
        var selectedCharacters = 0L
        required.forEach { section ->
            selectedCharacters += renderedLength(section)
            included += section.name
        }
        var coverage = omissionNote(optional)
        if (selectedCharacters + optional.sumOf(::renderedLength) <= maxChars) {
            selectedCharacters += optional.sumOf(::renderedLength)
            included += optional.map { it.name }
            coverage = ""
        } else {
            var admitted: Boolean
            do {
                admitted = false
                optional.filter { it.name !in included }.forEach { section ->
                    val nextCoverage = omissionNote(optional.filter { it.name !in included && it.name != section.name })
                    val nextCharacters = selectedCharacters + renderedLength(section)
                    val currentTotal = selectedCharacters + coverage.length
                    val nextTotal = nextCharacters + nextCoverage.length
                    // Charge only references that will actually be emitted, including shifts in the first eight.
                    if (nextTotal <= maxChars || currentTotal > maxChars && nextTotal < currentTotal) {
                        selectedCharacters = nextCharacters
                        included += section.name
                        coverage = nextCoverage
                        admitted = true
                    }
                }
                // Short inline sections can free reference space for an earlier skipped goal.
            } while (admitted)
        }
        if (selectedCharacters + coverage.length > maxChars)
            throw Overflow(sections.filter { it.name in included }, coverage.length, maxChars)
        optional.filter { it.name !in included }.mapTo(omitted) { it.name }
        // Presentation cannot change which complete sections the budget admitted.
        val ranks = presentationOrder.withIndex().associate { it.value to it.index }
        val text = StringBuilder((selectedCharacters + coverage.length).toInt())
        sections.filter { it.name in included }.sortedBy { ranks[it.name] ?: Int.MAX_VALUE }
            .forEach { text.append(render(it)) }
        text.append(coverage)
        check(text.length <= maxChars)
        return Result(text.toString(), included, omitted)
    }

    private fun render(section: Section) = "\n[${section.name}]\n${section.content}\n"
    private fun renderedLength(section: Section): Long = section.name.length.toLong() + section.content.length + 5L

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
