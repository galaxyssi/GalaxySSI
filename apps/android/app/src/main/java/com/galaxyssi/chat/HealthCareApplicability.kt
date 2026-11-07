package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCareApplicabilityMode { DISCUSSION_ONLY, INDIVIDUALIZED }
internal enum class HealthCareApplicabilityField { metric, unit, collection_condition, adult, pregnant, diabetes, specimen, fasting, illness_medication }
internal enum class HealthCareApplicabilityOperator { EQUALS, AT_LEAST, AT_MOST }
internal enum class HealthCareApplicabilityStatus { MISSING_REVIEW, DISCUSSION_ONLY, DECLARED_CHECKS_MATCH, NEEDS_CONTEXT, MISMATCH, CONFLICT }
internal enum class HealthCareCheckResult { MATCH, UNKNOWN, MISMATCH }

/** Conditions are model-declared source interpretations, not a clinical validation certificate. */
internal data class HealthCareApplicabilityCheck(val field: HealthCareApplicabilityField,
    val operator: HealthCareApplicabilityOperator, val expected: String, val sourceIndex: Int) {
    init {
        require(sourceIndex in 0..7 && expected.isNotBlank() && expected.length <= 80)
        require(operator == HealthCareApplicabilityOperator.EQUALS || field == HealthCareApplicabilityField.fasting)
        when (field) {
            HealthCareApplicabilityField.adult, HealthCareApplicabilityField.pregnant, HealthCareApplicabilityField.diabetes,
            HealthCareApplicabilityField.illness_medication -> require(expected in setOf("YES", "NO"))
            HealthCareApplicabilityField.specimen -> require(expected in HealthCareSpecimen.entries.filter { it != HealthCareSpecimen.UNKNOWN }.map { it.name })
            HealthCareApplicabilityField.metric -> require(expected in HealthMetric.entries.map { it.name })
            HealthCareApplicabilityField.fasting -> require(expected.toIntOrNull()?.let { it in 0..72 && it.toString() == expected } == true)
            HealthCareApplicabilityField.collection_condition -> require(expected != "unspecified" && expected != "UNKNOWN")
            HealthCareApplicabilityField.unit -> require(expected.length <= 32)
        }
    }
    fun json() = JSONObject().put("field", field.name).put("operator", operator.name).put("expected", expected).put("source_index", sourceIndex)
    companion object { fun from(j: JSONObject): HealthCareApplicabilityCheck {
        healthApplicabilityKeys(j, setOf("field", "operator", "expected", "source_index"))
        val index = j.getInt("source_index"); require(j.getDouble("source_index") == index.toDouble())
        return HealthCareApplicabilityCheck(HealthCareApplicabilityField.valueOf(j.getString("field")),
            HealthCareApplicabilityOperator.valueOf(j.getString("operator")), j.getString("expected"), index)
    } }
}

internal data class HealthCareSourceConflict(val sourceIndices: List<Int>, val detail: String, val nextStep: String) {
    init {
        require(sourceIndices.size in 2..8 && sourceIndices.distinct().size == sourceIndices.size && sourceIndices.all { it in 0..7 })
        require(detail.isNotBlank() && detail.length <= 1000 && nextStep.isNotBlank() && nextStep.length <= 1000)
    }
    fun json() = JSONObject().put("source_indices", JSONArray(sourceIndices)).put("detail", detail).put("next_step", nextStep)
    companion object { fun from(j: JSONObject): HealthCareSourceConflict {
        healthApplicabilityKeys(j, setOf("source_indices", "detail", "next_step"))
        val indices = j.getJSONArray("source_indices").let { a -> (0 until a.length()).map {
            val index = a.getInt(it); require(a.getDouble(it) == index.toDouble()); index
        } }
        return HealthCareSourceConflict(indices, j.getString("detail"), j.getString("next_step"))
    } }
}

internal data class HealthCareApplicability(val mode: HealthCareApplicabilityMode, val checks: List<HealthCareApplicabilityCheck>,
    val missingInformation: List<String>, val conflicts: List<HealthCareSourceConflict>) {
    init {
        require(checks.size <= 12 && checks.distinct().size == checks.size && missingInformation.size <= 8 && conflicts.size <= 8)
        require(missingInformation.all { it.isNotBlank() && it.length <= 500 })
        require(mode != HealthCareApplicabilityMode.INDIVIDUALIZED || checks.isNotEmpty() || missingInformation.isNotEmpty() || conflicts.isNotEmpty())
    }
    fun json() = JSONObject().put("mode", mode.name).put("checks", JSONArray(checks.map { it.json() }))
        .put("missing_information", JSONArray(missingInformation)).put("conflicts", JSONArray(conflicts.map { it.json() }))
    companion object { fun from(j: JSONObject): HealthCareApplicability {
        healthApplicabilityKeys(j, setOf("mode", "checks", "missing_information", "conflicts"))
        return HealthCareApplicability(HealthCareApplicabilityMode.valueOf(j.getString("mode")),
            j.getJSONArray("checks").let { a -> (0 until a.length()).map { HealthCareApplicabilityCheck.from(a.getJSONObject(it)) } },
            j.getJSONArray("missing_information").let { a -> (0 until a.length()).map { a.getString(it) } },
            j.getJSONArray("conflicts").let { a -> (0 until a.length()).map { HealthCareSourceConflict.from(a.getJSONObject(it)) } })
    } }
}

private fun healthApplicabilityKeys(j: JSONObject, expected: Set<String>) { require(j.keys().asSequence().toSet() == expected) }

internal object HealthCareApplicabilityPolicy {
    fun actual(check: HealthCareApplicabilityCheck, issue: HealthCareConcern): String? {
        val context = issue.context?.takeIf { it.record == issue.assessment.record }
        return when (check.field) {
            HealthCareApplicabilityField.metric -> issue.metric.name
            HealthCareApplicabilityField.unit -> issue.assessment.unit.takeIf { it.isNotBlank() }
            HealthCareApplicabilityField.collection_condition -> issue.assessment.sample?.condition?.takeUnless { it.isBlank() || it == "unspecified" }
            HealthCareApplicabilityField.adult -> context?.adult?.name
            HealthCareApplicabilityField.pregnant -> context?.pregnant?.name
            HealthCareApplicabilityField.diabetes -> context?.diagnosedDiabetes?.name
            HealthCareApplicabilityField.specimen -> context?.specimen?.name
            HealthCareApplicabilityField.fasting -> context?.fastingHours?.toString()
            HealthCareApplicabilityField.illness_medication -> context?.illnessOrMedication?.name
        }?.takeUnless { it == "UNKNOWN" }
    }
    fun result(check: HealthCareApplicabilityCheck, issue: HealthCareConcern): HealthCareCheckResult {
        val actual = actual(check, issue) ?: return HealthCareCheckResult.UNKNOWN
        val matches = when (check.operator) {
            HealthCareApplicabilityOperator.EQUALS -> actual == check.expected
            HealthCareApplicabilityOperator.AT_LEAST -> actual.toInt() >= check.expected.toInt()
            HealthCareApplicabilityOperator.AT_MOST -> actual.toInt() <= check.expected.toInt()
        }
        return if (matches) HealthCareCheckResult.MATCH else HealthCareCheckResult.MISMATCH
    }
    fun validate(review: HealthCareApplicability, action: HealthCareAction, sources: List<HealthCarePlanSource>) {
        require(review.checks.all { it.sourceIndex in sources.indices } && review.conflicts.all { c -> c.sourceIndices.all { it in sources.indices } })
        if (review.mode == HealthCareApplicabilityMode.DISCUSSION_ONLY) require(action.kind in setOf(HealthCareActionKind.CONTEXT, HealthCareActionKind.CLINICIAN_DISCUSSION))
    }
    fun status(review: HealthCareApplicability?, issue: HealthCareConcern): HealthCareApplicabilityStatus = when {
        review == null -> HealthCareApplicabilityStatus.MISSING_REVIEW
        review.mode == HealthCareApplicabilityMode.DISCUSSION_ONLY -> HealthCareApplicabilityStatus.DISCUSSION_ONLY
        review.conflicts.isNotEmpty() -> HealthCareApplicabilityStatus.CONFLICT
        review.checks.any { result(it, issue) == HealthCareCheckResult.MISMATCH } -> HealthCareApplicabilityStatus.MISMATCH
        review.missingInformation.isNotEmpty() || review.checks.isEmpty() || review.checks.any { result(it, issue) == HealthCareCheckResult.UNKNOWN } -> HealthCareApplicabilityStatus.NEEDS_CONTEXT
        else -> HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH
    }
    fun canAccept(plan: HealthCarePlan, issue: HealthCareConcern, action: HealthCareAction): Boolean = when (status(plan.applicability[action.id], issue)) {
        HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH -> true
        HealthCareApplicabilityStatus.DISCUSSION_ONLY, HealthCareApplicabilityStatus.MISSING_REVIEW ->
            action.kind in setOf(HealthCareActionKind.CONTEXT, HealthCareActionKind.CLINICIAN_DISCUSSION)
        else -> false
    }
}
