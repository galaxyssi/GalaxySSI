package com.galaxyssi.chat

import android.content.Context
import java.text.DateFormat
import java.util.Date

internal class HealthCareVisitPresentation(private val context: Context) {
    private fun s(id: Int, vararg args: Any) = context.getString(id, *args)
    private fun date(at: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(at))
    private fun unknown(value: String?) = value?.takeIf { it.isNotBlank() } ?: s(R.string.health_care_unknown)
    fun introduction(issue: HealthCareConcern, at: Long) = s(R.string.health_visit_introduction,
        s(issue.metric.titleResource()), date(at), issue.revision)
    fun limitations(moreRecords: Boolean, moreQuestions: Boolean) = buildList {
        add(s(R.string.health_visit_limitations))
        if (moreRecords) add(s(R.string.health_visit_more_records))
        if (moreQuestions) add(s(R.string.health_visit_more_questions))
    }.joinToString("\n")

    fun items(issue: HealthCareConcern, sections: Set<HealthCareVisitSection>, samples: List<HealthCareSample>,
        profile: HealthProfileContext?, questions: List<HealthCareQuestion>): List<HealthCareVisitItem> = buildList {
        if (HealthCareVisitSection.MEASUREMENTS in sections) {
            samples.forEach { sample ->
                val fields = sample.metric.fields.mapNotNull { field -> sample.values[field]?.let { "${s(healthFieldResource(field))}: $it ${sample.unitFor(field)}" } }
                val gaps = issue.assessment.sample?.takeIf { it.record != sample.record }?.let { latest ->
                    val prior = issue.context?.takeIf { it.record == sample.record }
                        ?: issue.assessment.comparison?.previousContext?.takeIf { it.record == sample.record }
                    HealthCareComparisonPolicy.gaps(sample, latest, prior, HealthCareClarificationContext.current(issue))
                }.orEmpty()
                add(HealthCareVisitItem("record:${sample.record.id}", HealthCareVisitSection.MEASUREMENTS,
                    "${s(issue.metric.titleResource())} · ${date(sample.measuredAt)}", buildList {
                        add(fields.joinToString(" / "))
                        add("${s(R.string.health_report_reference)}: ${unknown(sample.reference)}")
                        add("${s(R.string.health_visit_collection)}: ${s(healthContextResource(sample.condition))}")
                        add("${s(R.string.health_visit_source)}: ${s(healthRecordSourceResource(sample.source))} · ${s(R.string.health_revision, sample.record.revision)}")
                        if (gaps.isNotEmpty()) add(gaps.joinToString("; ") { s(HealthCareComparisonPresentation.gapResource(it)) })
                    }.joinToString("\n"), sample.record))
            }
        }
        if (HealthCareVisitSection.CONTEXT in sections) {
            val saved = HealthCareClarificationContext.current(issue)
            fun truth(value: HealthCareTruth?) = s(when (value) {
                HealthCareTruth.YES -> R.string.health_care_yes; HealthCareTruth.NO -> R.string.health_care_no
                else -> R.string.health_care_unknown
            })
            val lines = if (issue.metric == HealthMetric.GLUCOSE) listOf(
                "${s(R.string.health_care_adult)}: ${truth(saved?.adult)}",
                "${s(R.string.health_care_pregnant)}: ${truth(saved?.pregnant)}",
                "${s(R.string.health_care_diabetes)}: ${truth(saved?.diagnosedDiabetes)}",
                "${s(R.string.health_care_sample)}: ${s(when (saved?.specimen) {
                    HealthCareSpecimen.LAB_PLASMA -> R.string.health_care_lab_plasma
                    HealthCareSpecimen.HOME_CAPILLARY -> R.string.health_care_capillary
                    HealthCareSpecimen.INTERSTITIAL -> R.string.health_care_interstitial
                    else -> R.string.health_care_unknown
                })}", "${s(R.string.health_care_fasting)}: ${saved?.fastingHours?.toString() ?: s(R.string.health_care_unknown)}",
                "${s(R.string.health_care_illness)}: ${truth(saved?.illnessOrMedication)}") else listOf(s(R.string.health_visit_no_context))
            add(HealthCareVisitItem("context", HealthCareVisitSection.CONTEXT, s(R.string.health_visit_context),
                (lines + s(R.string.health_visit_context_notice)).joinToString("\n")))
        }
        if (HealthCareVisitSection.ACTIONS in sections) issue.actions.filter {
            it.state in setOf(HealthCareActionState.CONFIRMED, HealthCareActionState.DONE)
        }.forEach { action ->
            val feedback = action.feedback?.takeIf { it.scope == HealthCareQuestionPolicy.scope(issue) }
            add(HealthCareVisitItem("action:${action.id}", HealthCareVisitSection.ACTIONS, action.description, buildList {
                add(s(action.state.titleResource()))
                add(s(R.string.health_visit_action_notice))
                add("${s(R.string.health_visit_source)}: ${when {
                    action.visitReview != null -> s(R.string.health_visit_review_provenance)
                    action.instruction != null -> s(R.string.health_instruction_action_provenance)
                    else -> action.source }}")
                action.instruction?.let { ref -> add(s(R.string.health_revision, ref.revision) + " · " +
                    s(R.string.health_document_page, ref.original.page!!, ref.original.pageCount!!)) }
                if (action.basis != HealthCareFollowUpPolicy.basis(issue) || action.sourceInvalidated)
                    add(s(R.string.health_visit_stale_action))
                action.dueFrom?.let { add(s(R.string.health_care_plan_window, date(it), date(action.dueUntil!!))) }
                if (feedback != null) {
                    add(s(R.string.health_feedback_latest, s(feedback.kind.label()), date(feedback.recordedAt)))
                    add(feedback.note)
                } else if (action.feedback == null && action.outcome.isNotBlank()) add(action.outcome)
            }.joinToString("\n")))
        }
        if (HealthCareVisitSection.QUESTIONS in sections) questions.forEach { question ->
            require(question.concernId == issue.id && question.scope == HealthCareQuestionPolicy.scope(issue))
            val view = HealthCareQuestionPolicy.view(question, issue, HealthCareQuestionPolicy.known(issue, profile))
            val state = view.getString("state")
            add(HealthCareVisitItem("question:${question.id}", HealthCareVisitSection.QUESTIONS, question.question, buildList {
                add(question.purpose)
                add(s(when (state) {
                    "OPEN" -> R.string.health_visit_question_open
                    "ANSWERED" -> R.string.health_visit_question_answered
                    "DEFERRED" -> R.string.health_visit_question_deferred
                    "DECLINED" -> R.string.health_visit_question_declined
                    "CONFLICT" -> R.string.health_visit_question_conflict
                    else -> R.string.health_visit_stale_question
                }))
                if (!view.isNull("saved_fact")) add(s(R.string.health_visit_question_known))
                if (!view.isNull("reviewed_answer")) add(view.getString("reviewed_answer"))
                add(date(question.updatedAt))
            }.joinToString("\n")))
        }
        if (HealthCareVisitSection.PROFILE in sections) {
            if (profile == null) add(HealthCareVisitItem("profile:missing", HealthCareVisitSection.PROFILE,
                s(R.string.health_visit_profile), s(R.string.health_visit_profile_missing)))
            else {
                val link = requireNotNull(issue.profileLink)
                require(link.stamp == profile.stamp && profile.fields.keys == link.scope.fields && profile.entries.all { it.id in link.scope.entries })
                profile.fields.toSortedMap(compareBy { it.name }).forEach { (field, value) ->
                    require(field != HealthProfileField.NAME)
                    val display = if (field == HealthProfileField.REFERENCE_SEX) value?.text?.let { text ->
                        s(when (HealthReferenceSex.valueOf(text)) {
                            HealthReferenceSex.FEMALE -> R.string.health_profile_female
                            HealthReferenceSex.MALE -> R.string.health_profile_male
                            HealthReferenceSex.OTHER -> R.string.health_other
                            HealthReferenceSex.NOT_DISCLOSED -> R.string.health_profile_not_disclosed
                        })
                    } else value?.let { "${it.text} ${it.unit}".trim() }
                    add(HealthCareVisitItem("field:${field.name}", HealthCareVisitSection.PROFILE, s(field.titleResource()),
                        "${unknown(display)}\n${s(R.string.health_visit_self_report)}"))
                }
                profile.entries.forEach { entry -> add(HealthCareVisitItem("profile:${entry.id}", HealthCareVisitSection.PROFILE,
                    "${s(entry.kind.titleResource())}: ${entry.name}", listOf(entry.detail, entry.dose, entry.timing,
                        s(R.string.health_visit_self_report), date(entry.updatedAt)).filter(String::isNotBlank).joinToString("\n"))) }
                if (link.scope.entries.size != profile.entries.size) add(HealthCareVisitItem("profile:missing", HealthCareVisitSection.PROFILE,
                    s(R.string.health_visit_profile), s(R.string.health_visit_profile_unavailable)))
            }
        }
    }
}

internal fun HealthCareVisitSection.titleResource() = when (this) {
    HealthCareVisitSection.MEASUREMENTS -> R.string.health_visit_measurements
    HealthCareVisitSection.CONTEXT -> R.string.health_visit_context
    HealthCareVisitSection.ACTIONS -> R.string.health_visit_actions
    HealthCareVisitSection.QUESTIONS -> R.string.health_visit_questions
    HealthCareVisitSection.PROFILE -> R.string.health_visit_profile
}
