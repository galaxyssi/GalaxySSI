package com.galaxyssi.chat

import org.json.JSONObject

internal enum class HealthCareTargetComparison { REVIEW_REQUIRED, NOT_COMPARABLE, BELOW, WITHIN, ABOVE }

/** A proposal has no authority to write confirmation, change medication, or end tracking. */
internal data class HealthCareTargetProposal(val field: String, val low: String?, val high: String?, val unit: String,
    val lowInclusive: Boolean, val highInclusive: Boolean, val rationale: String, val sourceIndex: Int,
    val applicability: HealthCareApplicability) {
    init {
        require(field.isNotBlank() && field.length <= 80 && unit.isNotBlank() && unit.length <= 32)
        HealthCareTargetPolicy.validateBounds(low, high, lowInclusive, highInclusive)
        require(rationale.isNotBlank() && rationale.length <= 2000 && sourceIndex in 0..7)
        require(applicability.mode == HealthCareApplicabilityMode.INDIVIDUALIZED)
    }
    fun json() = JSONObject().put("field", field).put("low", low.orEmpty()).put("high", high.orEmpty()).put("unit", unit)
        .put("low_inclusive", lowInclusive).put("high_inclusive", highInclusive).put("rationale", rationale)
        .put("source_index", sourceIndex).put("applicability", applicability.json())
    companion object {
        fun from(j: JSONObject): HealthCareTargetProposal {
            require(j.keys().asSequence().toSet() == setOf("field", "low", "high", "unit", "low_inclusive", "high_inclusive",
                "rationale", "source_index", "applicability"))
            val index = j.getInt("source_index"); require(j.getDouble("source_index") == index.toDouble())
            require(j.get("low_inclusive") is Boolean && j.get("high_inclusive") is Boolean)
            return HealthCareTargetProposal(j.getString("field"), j.getString("low").ifEmpty { null }, j.getString("high").ifEmpty { null },
                j.getString("unit"), j.getBoolean("low_inclusive"), j.getBoolean("high_inclusive"), j.getString("rationale"), index,
                HealthCareApplicability.from(j.getJSONObject("applicability")))
        }
    }
}

internal object HealthCareTargetPolicy {
    fun number(value: String): java.math.BigDecimal {
        require(value.length in 1..20 && value.matches(Regex("[0-9]+(?:\\.[0-9]+)?")))
        return requireNotNull(HealthResult.parse(value, HealthResultForm.LABORATORY)?.exactNumber) {
            "Use an exact bounded decimal, not a comparison, range or exponent"
        }
    }
    fun validateBounds(low: String?, high: String?, lowInclusive: Boolean, highInclusive: Boolean) {
        require(low != null || high != null)
        val lower = low?.let(::number); val upper = high?.let(::number)
        require(lower == null || upper == null || lower < upper || lower.compareTo(upper) == 0 && lowInclusive && highInclusive)
    }
    fun basis(issue: HealthCareConcern): String = AgentNativeJsonCodec.sha256(mapOf("source" to issue.inputVersion,
        "record" to issue.assessment.record?.json()?.toString(), "context" to issue.context?.json()?.toString()))

    fun validate(proposal: HealthCareTargetProposal, sources: List<HealthCarePlanSource>) {
        require(proposal.sourceIndex in sources.indices)
        HealthCareApplicabilityPolicy.validateSources(proposal.applicability, sources)
    }
    fun canAccept(proposal: HealthCareTargetProposal, issue: HealthCareConcern): Boolean =
        proposal.field in issue.metric.requiredFields && proposal.unit in issue.metric.units &&
            proposal.unit == issue.assessment.unit && issue.assessment.record != null &&
            listOfNotNull(proposal.low, proposal.high).all { HealthResult.parse(it, issue.metric.form)?.exactNumber != null } &&
            HealthCareApplicabilityPolicy.status(proposal.applicability, issue) == HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH

    fun accept(plan: HealthCarePlan, issue: HealthCareConcern, now: Long): HealthCareTarget {
        val draft = requireNotNull(plan.target)
        require(canAccept(draft, issue)) { "Review the target unit, component, applicability and missing context first" }
        val source = plan.sources[draft.sourceIndex]
        return HealthCareTarget(draft.field, draft.low, draft.high, draft.unit, draft.rationale,
            "${source.title}\n${source.version}\n${source.url}", "user", now,
            draft.lowInclusive, draft.highInclusive, plan.id, basis(issue))
    }
    fun comparison(issue: HealthCareConcern): HealthCareTargetComparison {
        val target = issue.target ?: return HealthCareTargetComparison.REVIEW_REQUIRED
        if (target.basis.isEmpty() || target.basis != basis(issue)) return HealthCareTargetComparison.REVIEW_REQUIRED
        val sample = issue.assessment.sample ?: return HealthCareTargetComparison.NOT_COMPARABLE
        if (sample.unit != target.unit || sample.metric != issue.metric) return HealthCareTargetComparison.NOT_COMPARABLE
        val measured = sample.values[target.field]?.let { runCatching { number(it) }.getOrNull() }
            ?: return HealthCareTargetComparison.NOT_COMPARABLE
        target.low?.let { if (measured < number(it) || measured.compareTo(number(it)) == 0 && !target.lowInclusive) return HealthCareTargetComparison.BELOW }
        target.high?.let { if (measured > number(it) || measured.compareTo(number(it)) == 0 && !target.highInclusive) return HealthCareTargetComparison.ABOVE }
        return HealthCareTargetComparison.WITHIN
    }
    fun revoke(issue: HealthCareConcern): HealthCareConcern {
        require(issue.target != null)
        return issue.copy(target = null, targetRevision = Math.addExact(issue.targetRevision, 1),
            stage = if (issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) issue.stage else HealthCareStage.REASSESS)
    }
}
