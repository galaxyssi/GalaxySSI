package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Keep syntax errors separate from rejected fields so an agent can repair its actual draft. */
internal object CollaborationAssessmentValidation {
    class Failure(val path: String, val code: String, val expected: String, val actual: String,
                  val detail: String = "") : IllegalArgumentException("$path: $code; expected $expected; received $actual") {
        fun json() = JSONObject().put("path", path).put("code", code).put("expected", expected)
            .put("actual", actual).put("detail", detail)
    }

    data class Result(val assessment: JSONObject?, val failure: Failure?, val syntaxValid: Boolean) {
        fun feedback(prior: JSONArray): String = JSONObject()
            .put("component", "goal_assessment_validation")
            .put("json_syntax", when {
                syntaxValid -> "valid"
                failure?.code == "json_nesting_exceeded" -> "unverified"
                else -> "invalid"
            })
            .put("contract_state", state(prior))
            .put("established_criteria_count", prior.length())
            .put("failure", failure?.json() ?: JSONObject.NULL)
            .put("draft", "Complete rejected assessment retained in Prior assessment; retrieve omitted pages before repair.")
            .put("next_action", repair(prior)).toString()
    }

    fun state(prior: JSONArray) = if (prior.length() == 0) "initial_criteria_pending" else "established"

    fun repair(prior: JSONArray): String = if (prior.length() == 0)
        "Repair the assessment fields identified by the host. No acceptance criteria have been established yet; " +
            "the empty array is not corruption. Define complete criteria from the original goal and resubmit feasible work. " +
            "The rejected draft is a proposal, not an immutable contract. Do not execute rejected assignments."
    else "Repair the assessment fields identified by the host while preserving every established criterion, " +
        "validator and source constraint. Do not replace the saved contract or execute rejected assignments."

    fun inspect(raw: String): Result {
        val text = raw.trim().let { if (it.startsWith("```")) it.substringAfter('\n').removeSuffix("```").trim() else it }
        val parsed = try {
            CollaborationGoalContractStore.parseJson(text)
        } catch (_: Exception) {
            return Result(null, Failure("$", "invalid_json", "one complete JSON object", "unparseable input"), false)
        } catch (_: StackOverflowError) {
            return Result(null, Failure("$", "json_nesting_exceeded", "supported JSON nesting", "excessive nesting"), false)
        }
        if (parsed !is JSONObject) return Result(null,
            Failure("$", "invalid_type", "object", describe(parsed)), true)
        return try {
            text(parsed, "format", "$", setOf(CollaborationGoalLoop.FORMAT))
            text(parsed, "summary", "$")
            text(parsed, "decision", "$", setOf("continue", "achieved", "blocked"))
            val criteria = array(parsed, "criteria", "$")
            if (criteria.length() == 0) throw Failure("$.criteria", "empty_criteria", "one or more goal-derived criteria", "0 items")
            val ids = hashSetOf<String>()
            repeat(criteria.length()) { index ->
                val path = "$.criteria[$index]"
                val item = criteria.optJSONObject(index) ?: throw Failure(path, "invalid_type", "object", describe(criteria.opt(index)))
                val id = text(item, "id", path)
                if (!ids.add(id)) throw Failure("$path.id", "duplicate_id", "unique criterion ID", describe(id))
                text(item, "requirement", path)
                text(item, "status", path, setOf("met", "open"))
                if (item.has("verification")) text(item, "verification", path, setOf("documentary", "computational", "physical"))
                if (item.has("evidence_kind")) text(item, "evidence_kind", path, setOf("observed", "simulation", "proposal"))
                CollaborationEvidenceRequirements.required(item, path)
                try { CollaborationQualifiedValidation.binding(item) } catch (error: IllegalArgumentException) {
                    throw Failure("$path.validator", "invalid_validator", "qualified specification or absence for an open unqualified criterion",
                        describe(item.opt("validator")), error.message.orEmpty())
                }
                array(item, "evidence", path)
            }
            array(parsed, "work", "$")
            array(parsed, "blockers", "$")
            if (parsed.has(CollaborationCandidateEvolution.REQUESTS)) array(parsed, CollaborationCandidateEvolution.REQUESTS, "$")
            Result(parsed, null, true)
        } catch (failure: Failure) {
            Result(null, failure, true)
        }
    }

    private fun text(json: JSONObject, key: String, path: String, allowed: Set<String>? = null): String {
        val value = json.opt(key)
        if (value !is String || value.isBlank()) throw Failure("$path.$key", "invalid_text", "nonblank string", describe(value))
        if (allowed != null && value !in allowed) throw Failure("$path.$key", "unknown_value", allowed.joinToString(", "), describe(value))
        return value
    }

    private fun array(json: JSONObject, key: String, path: String) = json.optJSONArray(key)
        ?: throw Failure("$path.$key", "invalid_type", "array", describe(json.opt(key)))

    fun describe(value: Any?): String = when (value) {
        null -> "missing"
        JSONObject.NULL -> "null"
        is JSONArray -> "array(${value.length()} items)"
        is JSONObject -> "object"
        is String -> if (value.length <= 160) value else "string(${value.length} characters)"
        else -> value.toString().take(160)
    }
}
