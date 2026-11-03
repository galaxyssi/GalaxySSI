package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A requested deliverable persists independently of the actions chosen to obtain it. */
data class AgentGoalResultRequirement(
    val id: String,
    val description: String,
    val outcomeIds: List<String> = emptyList(),
    val artifactPaths: List<String> = emptyList(),
    val answer: String = ""
) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("description", description)
        .put("outcome_ids", JSONArray(outcomeIds)).put("artifact_paths", JSONArray(artifactPaths)).put("answer", answer)

    companion object {
        fun parse(json: JSONObject): AgentGoalResultRequirement? {
            val id = json.opt("id") as? String ?: return null
            val description = json.opt("description") as? String ?: return null
            val answer = if (json.has("answer")) json.opt("answer") as? String ?: return null else ""
            if (!validId(id) || description.isBlank() || description.length > 2048 || answer.length > 16_000) return null
            val outcomes = strings(json, "outcome_ids") ?: return null
            val artifacts = strings(json, "artifact_paths") ?: return null
            if (outcomes.any { !validId(it) } || artifacts.any {
                    AgentArtifactRequirement.parse(JSONObject().put("path", it)) == null
                }) return null
            return AgentGoalResultRequirement(id, description.trim(), outcomes, artifacts, answer.trim())
        }

        private fun strings(json: JSONObject, key: String): List<String>? {
            if (!json.has(key)) return emptyList()
            val array = json.optJSONArray(key) ?: return null
            val result = (0 until array.length()).map { array.opt(it) as? String ?: return null }
            return result.takeIf { it.distinct().size == it.size }
        }

        private fun validId(value: String): Boolean = value.matches(Regex("[A-Za-z0-9_.-]{1,128}"))
    }
}

internal object AgentGoalResultEvidence {
    fun planningViolation(requirements: AgentCompletionRequirements?, required: Boolean): String? =
        if (required && requirements?.results.isNullOrEmpty())
            "completion_requirements.results_required: Before execution, list every requested result as " +
                "{id,description,outcome_ids:[],artifact_paths:[],answer:\"\"}. Keep pending entries empty until observed; " +
                "do not invent evidence or substitute tool steps for user deliverables."
        else null

    fun missing(requirements: AgentCompletionRequirements, finalAnswer: String?, required: Boolean): List<String> {
        if (requirements.results.isEmpty()) return if (required) listOf(
            "Declare completion_requirements.results for every requested result; a successful tool call is not full-goal coverage"
        ) else emptyList()
        val outcomes = requirements.outcomes.mapTo(hashSetOf()) { it.id }
        val artifacts = requirements.artifacts.mapTo(hashSetOf()) { it.path }
        return buildList {
            for (result in requirements.results) {
                val prefix = "Requested result ${result.id}"
                if (result.outcomeIds.isEmpty() && result.artifactPaths.isEmpty()) {
                    add("$prefix needs outcome_ids or artifact_paths bound to verified evidence; do not discard the result")
                }
                result.outcomeIds.filterNot(outcomes::contains).forEach { add("$prefix references undeclared outcome $it") }
                result.artifactPaths.filterNot(artifacts::contains).forEach { add("$prefix references undeclared artifact $it") }
                if (result.answer.isBlank()) add("$prefix needs an evidence-grounded answer before completion")
                else if (finalAnswer != null && !finalAnswer.contains(result.answer)) {
                    add("$prefix is missing from the final answer; include its answer verbatim without dropping other results")
                }
            }
        }
    }
}
