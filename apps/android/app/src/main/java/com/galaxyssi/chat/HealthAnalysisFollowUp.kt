package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

internal const val HEALTH_FOLLOW_UP_MAX_LENGTH = 600
internal enum class HealthFollowUpStatus { ANSWERED, PARTIAL, OUT_OF_SCOPE }
internal enum class HealthFollowUpTopic { CHANGES, COVERAGE, SOURCES }
internal data class HealthFollowUpSection(val topic: HealthFollowUpTopic, val facts: List<String>)
internal data class HealthFollowUpAnswer(
    val status: HealthFollowUpStatus, val sections: List<HealthFollowUpSection>, val actions: List<HealthAnalysisAction>,
) {
    fun json() = JSONObject().put("status", status.name).put("sections", JSONArray(sections.map {
        JSONObject().put("topic", it.topic.name).put("fact_ids", JSONArray(it.facts))
    })).put("actions", JSONArray(actions.map { it.name }))
}

internal class HealthFollowUpQuestion private constructor(val text: String, val previous: HealthFollowUpAnswer?) {
    companion object {
        fun from(raw: String, previous: HealthFollowUpAnswer? = null): HealthFollowUpQuestion? =
            raw.replace("\r\n", "\n").replace('\r', '\n').trim().takeIf { question ->
                question.length in 1..HEALTH_FOLLOW_UP_MAX_LENGTH &&
                    question.none { it.isISOControl() && it != '\n' && it != '\t' }
            }?.let { HealthFollowUpQuestion(it, previous) }
    }
}

internal object HealthAnalysisFollowUp {
    private fun topics(preview: HealthAnalysisInput) =
        HealthFollowUpTopic.entries.filter { it != HealthFollowUpTopic.CHANGES || preview.focus == HealthAnalysisFocus.CHANGES }

    fun payload(preview: HealthAnalysisInput, question: HealthFollowUpQuestion): JSONObject =
        HealthAnalysis.payload(preview).put("question", question.text).put("allowed_topics", JSONArray(topics(preview).map { it.name }))
            .apply { question.previous?.let { put("previous_answer", it.json()) } }

    fun decode(raw: String, preview: HealthAnalysisInput): HealthFollowUpAnswer {
        if (raw.length > 4096) throw HealthAnalysisInvalidReply()
        try {
            val text = raw.trim().let { value ->
                if (value.startsWith("```json\n") && value.endsWith("```")) value.removePrefix("```json\n").dropLast(3).trim() else value
            }
            val reader = JSONTokener(text)
            val root = reader.nextValue() as JSONObject
            check(reader.nextClean() == '\u0000' && root.keys().asSequence().toSet() == setOf("status", "sections", "actions"))
            val status = HealthFollowUpStatus.valueOf(root.get("status") as String)
            val entries = root.getJSONArray("sections")
            val allowed = topics(preview)
            val facts = preview.factKeys.toSet()
            check(entries.length() <= allowed.size)
            val sections = (0 until entries.length()).map { index ->
                val item = entries.getJSONObject(index)
                check(item.keys().asSequence().toSet() == setOf("topic", "fact_ids"))
                val topic = HealthFollowUpTopic.valueOf(item.get("topic") as String)
                check(topic in allowed)
                val keys = strings(item.getJSONArray("fact_ids"), 3)
                check(keys.isNotEmpty() && keys.all { it in facts })
                HealthFollowUpSection(topic, keys)
            }
            check(sections.map { it.topic }.distinct().size == sections.size)
            val actions = strings(root.getJSONArray("actions"), 2).map(HealthAnalysisAction::valueOf)
            check(actions.all { it in preview.allowedActions })
            check((sections.isEmpty() && actions.isEmpty()) == (status == HealthFollowUpStatus.OUT_OF_SCOPE))
            return HealthFollowUpAnswer(status, sections, actions)
        } catch (_: Exception) { throw HealthAnalysisInvalidReply() }
    }

    private fun strings(array: JSONArray, maximum: Int): List<String> {
        check(array.length() <= maximum)
        return (0 until array.length()).map { array.get(it) as String }.also { check(it.distinct().size == it.size) }
    }
}
