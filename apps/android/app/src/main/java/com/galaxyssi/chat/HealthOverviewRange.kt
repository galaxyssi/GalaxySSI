package com.galaxyssi.chat

internal enum class HealthOverviewRangeSource { REPORT, RECORD, CONFIRMED_TARGET }
internal enum class HealthOverviewRangePosition { BELOW, WITHIN, ABOVE, NOT_COMPARABLE }

internal data class HealthOverviewRange(val field: String, val source: HealthOverviewRangeSource,
    val bounds: String, val unit: String, val position: HealthOverviewRangePosition) {
    val outside get() = position == HealthOverviewRangePosition.BELOW || position == HealthOverviewRangePosition.ABOVE
}

internal object HealthOverviewRangePolicy {
    fun report(record: HealthObservation): HealthOverviewRange? {
        val draft = record.draft
        val field = draft.metric.fields.singleOrNull() ?: return null
        if (draft.unit.isBlank() || draft.unit !in draft.metric.units) return null
        val range = HealthResult.parse(draft.reference, HealthResultForm.LABORATORY) ?: return null
        if (range.kind != HealthResultKind.RANGE && range.kind != HealthResultKind.COMPARISON) return null
        val number = HealthResult.parse(draft.values[field].orEmpty(), draft.metric.form)?.exactNumber
        val position = if (number == null) HealthOverviewRangePosition.NOT_COMPARABLE else {
            val bound = range.number.toBigDecimal()
            when {
                range.kind == HealthResultKind.RANGE && number < bound -> HealthOverviewRangePosition.BELOW
                range.kind == HealthResultKind.RANGE && number > range.upper.toBigDecimal() -> HealthOverviewRangePosition.ABOVE
                range.operator == "<" && number >= bound || range.operator == "<=" && number > bound -> HealthOverviewRangePosition.ABOVE
                range.operator == ">" && number <= bound || range.operator == ">=" && number < bound -> HealthOverviewRangePosition.BELOW
                else -> HealthOverviewRangePosition.WITHIN
            }
        }
        val source = if (draft.evidence?.confirmed == true) HealthOverviewRangeSource.REPORT else HealthOverviewRangeSource.RECORD
        return HealthOverviewRange(field, source, range.raw, draft.unit, position)
    }

    fun target(record: HealthObservation, issue: HealthCareConcern): HealthOverviewRange? {
        val target = issue.target ?: return null
        if (issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) || issue.metric != record.draft.metric ||
            issue.assessment.record != HealthCareRecordRef(record.id, record.revision) ||
            target.field !in record.draft.metric.requiredFields || target.unit != record.draft.unit) return null
        val position = when (HealthCareTargetPolicy.comparison(issue)) {
            HealthCareTargetComparison.REVIEW_REQUIRED -> return null
            HealthCareTargetComparison.NOT_COMPARABLE -> HealthOverviewRangePosition.NOT_COMPARABLE
            HealthCareTargetComparison.BELOW -> HealthOverviewRangePosition.BELOW
            HealthCareTargetComparison.ABOVE -> HealthOverviewRangePosition.ABOVE
            HealthCareTargetComparison.WITHIN -> HealthOverviewRangePosition.WITHIN
        }
        val low = target.low
        val high = target.high
        val bounds = if (low != null && high != null && target.lowInclusive && target.highInclusive) "$low\u2013$high"
        else listOfNotNull(low?.let { "${if (target.lowInclusive) "\u2265" else ">"} $it" },
            high?.let { "${if (target.highInclusive) "\u2264" else "<"} $it" }).joinToString(" / ")
        return HealthOverviewRange(target.field, HealthOverviewRangeSource.CONFIRMED_TARGET, bounds, target.unit, position)
    }
}
