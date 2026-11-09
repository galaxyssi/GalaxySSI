package com.galaxyssi.chat

import android.content.Context

/** Every preview and share is checked against source clocks; no report copy is written to disk. */
internal class HealthCareVisitRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    fun load(id: String, sections: Set<HealthCareVisitSection>, now: Long = System.currentTimeMillis()): HealthCareVisitSummary {
        require(HealthProfilePolicy.uuid(id) && sections.isNotEmpty())
        HealthCareEngine.evaluate(context, names)
        return HealthPrivacyStore(context, names.privacy).use { privacy ->
            val permission = privacy.policy()
            check(permission.metrics && permission.profile)
            HealthCareStore(context, names.care).use { care ->
                val issue = care.concern(id) ?: throw HealthCareConflict()
                val settings = care.settings()
                HealthRecordStore(context, names.records).use { records ->
                    if (issue.assessment.record == null || issue.inputVersion !=
                        HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(issue.metric))) throw HealthCareConflict()
                    val selectedProfile = issue.profileLink.takeIf { HealthCareVisitSection.PROFILE in sections }
                    val profile = selectedProfile?.let { HealthCareProfileAccess.capture(context, it, names) }
                    val samples = if (HealthCareVisitSection.MEASUREMENTS in sections) privacy.track(
                        HealthAccessScope(HealthAccessPurpose.PROACTIVE_CARE, setOf(issue.metric))) {
                        records.recentSelf(now, 9, issue.metric).map(HealthCareSample::of)
                    } else emptyList()
                    val questions = if (HealthCareVisitSection.QUESTIONS in sections) care.questions(issue, limit = 8)
                        else HealthCareQuestionPage(emptyList(), null)
                    val presentation = HealthCareVisitPresentation(context)
                    val document = HealthCareVisitSummary(issue.id, issue.revision, issue.metric, issue.inputVersion,
                        settings.version, permission.version, selectedProfile, now, sections.toSet(),
                        context.getString(R.string.health_visit_title), presentation.introduction(issue, now),
                        presentation.limitations(samples.size > 8, questions.next != null),
                        presentation.items(issue, sections, samples.take(8), profile, questions.items))
                    if (privacy.policy() != permission || care.concern(id)?.revision != issue.revision || care.settings() != settings ||
                        issue.inputVersion != HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(issue.metric)) ||
                        !HealthCareProfileAccess.current(context, selectedProfile, names)) throw HealthCareConflict()
                    document
                }
            }
        }
    }

    fun validate(value: HealthCareVisitSummary, now: Long = System.currentTimeMillis()) {
        if (!HealthCareVisitSummary.fresh(value.createdAt, now)) throw HealthCareConflict()
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            val permission = privacy.policy()
            if (!permission.metrics || !permission.profile || permission.version != value.privacyVersion) throw HealthCareConflict()
            HealthCareStore(context, names.care).use { care ->
                val issue = care.concern(value.concernId) ?: throw HealthCareConflict()
                val settings = care.settings()
                if (issue.revision != value.revision || issue.metric != value.metric || issue.inputVersion != value.inputVersion ||
                    settings.version != value.settingsVersion) throw HealthCareConflict()
                HealthRecordStore(context, names.records).use {
                    if (value.inputVersion != HealthCareEngine.inputVersion(settings.version, permission.version, it.metricVersion(value.metric)))
                        throw HealthCareConflict()
                }
                if (HealthCareVisitSection.PROFILE in value.sections && (issue.profileLink != value.profile ||
                    !HealthCareProfileAccess.current(context, value.profile, names))) throw HealthCareConflict()
                if (privacy.policy() != permission || care.concern(value.concernId)?.revision != value.revision) throw HealthCareConflict()
            }
        }
    }
}
