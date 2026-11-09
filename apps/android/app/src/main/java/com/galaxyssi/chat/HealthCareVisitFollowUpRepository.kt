package com.galaxyssi.chat

import android.content.Context

internal data class HealthCareVisitFollowUpSnapshot(val visit: HealthCareEncounterSnapshot,
    val followUp: HealthCareVisitFollowUp?, val history: HealthCareVisitFollowUpPage, val reminder: HealthCareReminder? = null)

internal class HealthCareVisitFollowUpRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    private val encounters = HealthCareEncounterRepository(context, names)
    fun load(id: String, encounter: String, before: Int = Int.MAX_VALUE): HealthCareVisitFollowUpSnapshot {
        val visit = encounters.load(id, selectedId = encounter)
        val result = encounters.commit(visit) {
            val value = it.visitFollowUp(encounter)
            if (value != null && value.concernId != id) throw HealthCareConflict()
            HealthCareVisitFollowUpSnapshot(visit, value, it.visitFollowUpHistory(id, encounter, before),
                value?.let { journal -> it.reminder(HealthCareVisitReviewPolicy.actionId(journal.id)) })
        }
        encounters.commit(visit) { }
        return result
    }
    fun record(snapshot: HealthCareVisitFollowUpSnapshot, input: HealthCareVisitFollowUpInput, operation: String,
        now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        it.recordVisitFollowUp(snapshot.visit.issue.id, snapshot.visit.issue.revision, snapshot.visit.selected!!.id,
            snapshot.visit.selected.revision, snapshot.followUp?.revision, input, operation, now)
    }
    fun delete(snapshot: HealthCareVisitFollowUpSnapshot, now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        it.deleteVisitFollowUp(snapshot.visit.issue.id, snapshot.visit.issue.revision, snapshot.visit.selected!!.id,
            snapshot.followUp?.revision ?: throw HealthCareConflict(), now)
    }
    fun schedule(snapshot: HealthCareVisitFollowUpSnapshot, at: Long, now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        val journal = snapshot.followUp ?: throw HealthCareConflict()
        if (!HealthCareProfileAccess.current(context, snapshot.visit.issue.profileLink, names)) throw HealthCareConflict()
        it.scheduleVisitReview(snapshot.visit.issue.id, snapshot.visit.issue.revision,
            HealthCareVisitFollowUpScope.of(journal, snapshot.visit.selected!!), snapshot.reminder?.token, snapshot.visit.privacy,
            HealthCareEngine.inputVersion(snapshot.visit.settingsVersion, snapshot.visit.privacy.version, snapshot.visit.recordClock),
            at, context.getString(R.string.health_visit_review_action), now)
    }
    fun cancelReminder(snapshot: HealthCareVisitFollowUpSnapshot, now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        val value = snapshot.reminder ?: throw HealthCareConflict()
        if (value.concernId != snapshot.visit.issue.id || value.actionId != snapshot.followUp?.id?.let(HealthCareVisitReviewPolicy::actionId))
            throw HealthCareConflict()
        it.cancelReminder(value.actionId, value.token, now)
    }
    fun discuss(snapshot: HealthCareVisitFollowUpSnapshot): String = encounters.commit(snapshot.visit) { care ->
        check(names.fixture == null)
        val value = snapshot.followUp ?: throw HealthCareConflict()
        HealthCareVisitFollowUpTool.selected(care, snapshot.visit.issue.id,
            HealthCareVisitFollowUpScope.of(value, snapshot.visit.selected!!))
        HealthCareDiscussion.open(context, value.concernId, names)
    }
}
