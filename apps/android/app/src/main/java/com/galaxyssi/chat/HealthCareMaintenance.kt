package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A reviewed follow-up workflow, never an automated certificate of clinical stability. */
internal enum class HealthCareMaintenanceBasis { CURRENT_TARGET, RISK_REVIEW }

internal data class HealthCareMaintenanceProposal(val rationale: String, val records: List<HealthCareRecordRef>,
    val sourceIndex: Int, val recheckIndex: Int, val applicability: HealthCareApplicability,
    val goalBasis: HealthCareMaintenanceBasis = HealthCareMaintenanceBasis.CURRENT_TARGET) {
    init {
        require(rationale.isNotBlank() && rationale.length <= 2000)
        require(records.size in 2..30 && records.map { it.id }.distinct().size == records.size)
        require(sourceIndex in 0..7 && recheckIndex in 0..7 && applicability.mode == HealthCareApplicabilityMode.INDIVIDUALIZED)
    }
    fun json() = JSONObject().put("rationale", rationale).put("records", JSONArray(records.map { it.json() }))
        .put("source_index", sourceIndex).put("recheck_index", recheckIndex).put("applicability", applicability.json()).put("goal_basis", goalBasis.name)
    companion object {
        fun from(j: JSONObject): HealthCareMaintenanceProposal {
            require(j.keys().asSequence().toSet() == setOf("rationale", "records", "source_index", "recheck_index", "applicability", "goal_basis"))
            fun index(key: String): Int = j.getInt(key).also { require(j.getDouble(key) == it.toDouble()) }
            val refs = j.getJSONArray("records").let { a -> (0 until a.length()).map {
                val ref = a.getJSONObject(it)
                require(ref.keys().asSequence().toSet() == setOf("id", "revision"))
                require(ref.getDouble("revision") == ref.getInt("revision").toDouble())
                HealthCareRecordRef.from(ref)
            } }
            return HealthCareMaintenanceProposal(j.getString("rationale"), refs, index("source_index"), index("recheck_index"),
                HealthCareApplicability.from(j.getJSONObject("applicability")), HealthCareMaintenanceBasis.valueOf(j.getString("goal_basis")))
        }
    }
}

internal data class HealthCareMaintenance(val planId: String, val actionId: String, val basis: String, val confirmedAt: Long) {
    init { require(HealthProfilePolicy.uuid(planId) && HealthProfilePolicy.uuid(actionId) && basis.matches(Regex("[a-f0-9]{64}")) && confirmedAt > 0) }
    fun json() = JSONObject().put("plan_id", planId).put("action_id", actionId).put("basis", basis).put("confirmed_at", confirmedAt)
    companion object { fun from(j: JSONObject) = HealthCareMaintenance(j.getString("plan_id"), j.getString("action_id"), j.getString("basis"), j.getLong("confirmed_at")) }
}

internal enum class HealthCareMaintenanceGap { TARGET, HISTORY, COMPARABILITY, APPLICABILITY, OPEN_ACTIONS, RECHECK, PRIORITY }

internal object HealthCareMaintenancePolicy {
    fun validate(proposal: HealthCareMaintenanceProposal, plan: HealthCarePlan) {
        require(proposal.sourceIndex in plan.sources.indices && proposal.recheckIndex in plan.actions.indices && plan.target == null)
        require(plan.actions[proposal.recheckIndex].kind == HealthCareActionKind.RECHECK)
        HealthCareApplicabilityPolicy.validateSources(proposal.applicability, plan.sources)
    }

    fun gaps(plan: HealthCarePlan, issue: HealthCareConcern, now: Long): Set<HealthCareMaintenanceGap> {
        val draft = requireNotNull(plan.maintenance)
        val gaps = linkedSetOf<HealthCareMaintenanceGap>()
        val target = issue.target
        if (draft.goalBasis == HealthCareMaintenanceBasis.CURRENT_TARGET &&
            (target == null || HealthCareTargetPolicy.comparison(issue) != HealthCareTargetComparison.WITHIN) ||
            draft.goalBasis == HealthCareMaintenanceBasis.RISK_REVIEW && target != null) gaps += HealthCareMaintenanceGap.TARGET
        val series = issue.assessment.series
        val samples = series?.samples?.take(draft.records.size).orEmpty()
        // Require a contiguous prefix including the latest result; never select only the in-range rows.
        if (samples.map { it.record } != draft.records || samples.map { it.measuredAt }.distinct().size < 2 ||
            samples.lastOrNull()?.measuredAt == series?.samples?.getOrNull(samples.size)?.measuredAt ||
            series?.hasEarlier == true && samples.size == series.samples.size) gaps += HealthCareMaintenanceGap.HISTORY
        val latest = issue.assessment.sample
        if (latest == null) gaps += HealthCareMaintenanceGap.COMPARABILITY else samples.forEach { sample ->
            val priorContext = issue.context?.takeIf { it.record == sample.record }
                ?: issue.assessment.comparison?.previousContext?.takeIf { it.record == sample.record }
            if (HealthCareComparisonPolicy.gaps(sample, latest, priorContext, issue.context?.takeIf { it.record == latest.record })
                    .any { it != HealthCareComparisonGap.METHOD_UNVERIFIED }) gaps += HealthCareMaintenanceGap.COMPARABILITY
            if (target != null) {
                val value = sample.values[target.field]?.let { runCatching { HealthCareTargetPolicy.number(it) }.getOrNull() }
                if (value == null || sample.unit != target.unit ||
                    target.low?.let { value < HealthCareTargetPolicy.number(it) || value.compareTo(HealthCareTargetPolicy.number(it)) == 0 && !target.lowInclusive } == true ||
                    target.high?.let { value > HealthCareTargetPolicy.number(it) || value.compareTo(HealthCareTargetPolicy.number(it)) == 0 && !target.highInclusive } == true)
                    gaps += HealthCareMaintenanceGap.TARGET
            }
        }
        if (HealthCareApplicabilityPolicy.status(draft.applicability, issue) != HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH)
            gaps += HealthCareMaintenanceGap.APPLICABILITY
        if (issue.actions.any { it.state in setOf(HealthCareActionState.PROPOSED, HealthCareActionState.CONFIRMED) }) gaps += HealthCareMaintenanceGap.OPEN_ACTIONS
        val action = plan.actions[draft.recheckIndex]
        if (action.dueFrom == null || action.dueFrom <= now || !HealthCareApplicabilityPolicy.canAccept(plan, issue, action)) gaps += HealthCareMaintenanceGap.RECHECK
        if (HealthCarePriority.rank(issue.assessment) > 0) gaps += HealthCareMaintenanceGap.PRIORITY
        return gaps
    }

    fun accept(plan: HealthCarePlan, original: HealthCareConcern, next: HealthCareConcern, selected: Set<String>, now: Long): HealthCareConcern {
        val draft = requireNotNull(plan.maintenance)
        require(gaps(plan, original, now).isEmpty()) { "Review maintenance evidence, comparability, target and next assessment first" }
        val action = plan.actions[draft.recheckIndex]
        require(action.id in selected)
        return next.copy(stage = HealthCareStage.MAINTENANCE, reviewNote = draft.rationale, reviewedBy = "user",
            maintenance = HealthCareMaintenance(plan.id, action.id, HealthCareFollowUpPolicy.basis(next), now))
    }

    fun needsReassessment(issue: HealthCareConcern, now: Long): Boolean {
        if (issue.stage != HealthCareStage.MAINTENANCE) return false
        val review = issue.maintenance ?: return true
        val action = issue.actions.firstOrNull { it.id == review.actionId } ?: return true
        return review.basis != HealthCareFollowUpPolicy.basis(issue) || action.state != HealthCareActionState.CONFIRMED ||
            action.dueFrom == null || action.dueFrom <= now || issue.nextDue?.let { it <= now } == true
    }
}
