package com.galaxyssi.chat

import android.content.Context
import java.time.ZoneId

internal data class HealthOverviewCareAction(val concernId: String, val id: String, val title: String,
    val dueAt: Long, val overdue: Boolean)
internal data class HealthOverviewCareConcern(val id: String, val metric: HealthMetric, val stage: HealthCareStage,
    val sourceChanged: Boolean)
internal data class HealthOverviewCareVisit(val concernId: String, val id: String, val purpose: String,
    val state: HealthCareEncounterState, val at: Long?, val zone: String, val journal: HealthCareVisitFollowUpState?)

internal data class HealthOverviewCare(
    val permitted: Boolean = true, val enabled: Boolean = false, val unavailable: Boolean = false,
    val actionsReady: Boolean = true, val actions: List<HealthOverviewCareAction> = emptyList(),
    val upcoming: HealthOverviewCareAction? = null, val concerns: List<HealthOverviewCareConcern> = emptyList(),
    val visits: List<HealthOverviewCareVisit> = emptyList()
) {
    companion object {
        private const val MAX_CONCERNS = 3
        private const val MAX_ACTIONS = 3
        private const val ACTION_CANDIDATES = 8

        fun load(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, now: Long,
            zone: ZoneId): HealthOverviewCare {
            if (!context.getDatabasePath(names.care).exists()) return HealthOverviewCare()
            val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
            if (!privacy.metrics || !privacy.profile) return HealthOverviewCare(permitted = false)
            return HealthCareStore(context, names.care).use { care ->
                val settings = care.settings()
                val clocks = mutableMapOf<HealthMetric, String>()
                val current = mutableMapOf<String, Boolean>()
                val revisions = mutableMapOf<String, Int>()
                fun currentSource(issue: HealthCareConcern): Boolean = current.getOrPut(issue.id) {
                    revisions[issue.id] = issue.revision
                    issue.inputVersion == HealthCareEngine.inputVersion(settings.version, privacy.version,
                        clocks.getOrPut(issue.metric) { records.metricVersion(issue.metric) }) &&
                        HealthCareProfileAccess.current(context, issue.profileLink, names)
                }
                val issues = care.page(limit = MAX_CONCERNS).items
                val concerns = issues.map { HealthOverviewCareConcern(it.id, it.metric, it.stage, !currentSource(it)) }
                val visits = issues.mapNotNull { issue ->
                    val visit = care.encounters(issue.id, limit = 1, expectedRevision = issue.revision).items.firstOrNull()
                        ?.takeUnless { it.details.state == HealthCareEncounterState.CANCELLED } ?: return@mapNotNull null
                    val details = visit.details
                    val journal = care.visitFollowUp(visit.id)?.takeIf { it.concernId == issue.id }
                    HealthOverviewCareVisit(issue.id, visit.id, details.purpose, details.state,
                        details.attendedAt ?: details.plannedAt, details.zone, journal?.state)
                }
                val end = HealthCareAgenda.dayEnd(now, zone)
                val ready = settings.enabled && care.prepareAgendaBatch()
                fun read(filter: HealthCareAgendaFilter): Pair<List<HealthOverviewCareAction>, Boolean> {
                    if (!ready) return emptyList<HealthOverviewCareAction>() to false
                    val page = care.agenda(filter, end, limit = ACTION_CANDIDATES)
                    return page.items.mapNotNull { item ->
                        val due = item.plannedAt ?: return@mapNotNull null
                        if (!currentSource(item.concern) || item.reminder?.let { it.privacyVersion != privacy.version } == true ||
                            !HealthCareInstructionAccess.current(context, names, care, item.concern, item.action)) return@mapNotNull null
                        val deadline = item.reminder?.dueAt ?: item.action.dueUntil ?: due
                        val overdue = deadline < now
                        HealthOverviewCareAction(item.concern.id, item.action.id, item.action.description,
                            if (overdue) deadline else due, overdue)
                    } to (page.next != null)
                }
                val (actions, moreToday) = read(HealthCareAgendaFilter.TODAY)
                val (later, moreLater) = if (actions.isEmpty() && !moreToday) read(HealthCareAgendaFilter.LATER)
                    else emptyList<HealthOverviewCareAction>() to false
                if (HealthPrivacyStore(context, names.privacy).use { it.policy() } != privacy ||
                    care.settings() != settings || clocks.isNotEmpty() && records.metricVersions(clocks.keys) != clocks ||
                    revisions.any { (id, revision) -> care.concern(id)?.revision != revision }) throw HealthCareConflict()
                HealthOverviewCare(enabled = settings.enabled,
                    actionsReady = ready && !(actions.isEmpty() && (moreToday || later.isEmpty() && moreLater)),
                    actions = actions.take(MAX_ACTIONS), upcoming = later.firstOrNull(), concerns = concerns, visits = visits)
            }
        }
    }
}
